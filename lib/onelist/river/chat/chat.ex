defmodule Onelist.River.Chat do
  @moduledoc """
  Main chat processing module for River.

  Handles the orchestration of:
  - Intent classification
  - Entity extraction
  - Action execution
  - Response generation
  """

  alias Onelist.River.{Entries, GTD}
  alias Onelist.River.Chat.IntentClassifier
  alias Onelist.River.Chat.EntityExtractor
  alias Onelist.River.Chat.ResponseGenerator

  require Logger

  @doc """
  Process a user message and generate a response.

  ## Options
    * `:conversation_id` - Use specific conversation
  """
  def process(user_id, message, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)

    # Get or create conversation
    conversation_id = Keyword.get(opts, :conversation_id)

    {:ok, conversation} =
      if conversation_id do
        case Onelist.Entries.get_entry(conversation_id) do
          nil -> {:error, :conversation_not_found}
          conv -> {:ok, conv}
        end
      else
        Entries.get_or_create_conversation(user_id)
      end

    # Add user message
    {:ok, user_msg} = Entries.add_message(conversation.id, :user, message)
    user_sequence = user_msg.metadata["sequence"]

    # Classify intent
    intent = IntentClassifier.classify(message)

    # Extract entities
    entities = EntityExtractor.extract(message)

    # Execute action based on intent
    {action_taken, action_data, response_text} =
      execute_intent(user_id, intent, message, entities)

    # Calculate processing time
    processing_time = System.monotonic_time(:millisecond) - start_time

    # Add assistant response
    {:ok, assistant_msg} =
      Entries.add_message(conversation.id, :assistant, response_text,
        intent: intent,
        response_time_ms: processing_time
      )

    assistant_sequence = assistant_msg.metadata["sequence"]

    # Get GTD state
    gtd_state = GTD.get_gtd_state(user_id)

    # Build response
    response = %{
      message: response_text,
      intent: intent,
      action_taken: action_taken,
      conversation_id: conversation.id,
      user_message_sequence: user_sequence,
      assistant_message_sequence: assistant_sequence,
      processing_time_ms: processing_time,
      gtd_state: gtd_state
    }

    # Add action-specific data and citations
    response =
      case action_data do
        %{task: task} ->
          Map.put(response, :task, task)

        %{tasks: tasks} ->
          Map.put(response, :tasks, tasks)

        %{briefing: briefing} ->
          Map.put(response, :briefing, briefing)

        %{search_results: results} ->
          response
          |> Map.put(:search_results, results)
          |> Map.put(:citations, format_citations(results))

        %{citations: citations} ->
          Map.put(response, :citations, citations)

        _ ->
          response
      end

    {:ok, response}
  end

  defp format_citations(results) when is_list(results) do
    results
    |> Enum.with_index(1)
    |> Enum.map(fn {r, idx} ->
      %{
        index: idx,
        id: r[:id],
        public_id: r[:public_id],
        title: r[:title] || r[:entry_title],
        date: r[:inserted_at]
      }
    end)
  end

  defp format_citations(_), do: []

  # ============================================
  # INTENT EXECUTION
  # ============================================

  defp execute_intent(user_id, :create_task, message, entities) do
    # Extract task title from message
    title = extract_task_title(message)
    context = entities[:context]
    due_date = entities[:due_date]

    attrs = %{title: title}
    attrs = if context, do: Map.put(attrs, :gtd_context, context), else: attrs
    attrs = if due_date, do: Map.put(attrs, :due_date, due_date), else: attrs

    case Entries.create_task(user_id, attrs) do
      {:ok, task} ->
        response = ResponseGenerator.task_created(task)
        {:task_created, %{task: task}, response}

      {:error, reason} ->
        Logger.error("Failed to create task: #{inspect(reason)}")
        response = "Sorry, I couldn't create that task. Please try again."
        {:error, %{error: reason}, response}
    end
  end

  defp execute_intent(user_id, :complete_task, message, _entities) do
    # Extract task reference from message
    task_ref = extract_task_reference(message)

    case Entries.find_task_by_title(user_id, task_ref) do
      nil ->
        response = "I couldn't find a task matching '#{task_ref}'. Can you be more specific?"
        {:no_action, %{}, response}

      task ->
        case Entries.complete_task(task.id) do
          {:ok, completed} ->
            response = ResponseGenerator.task_completed(completed)
            {:task_completed, %{task: completed}, response}

          {:error, :already_completed} ->
            response = "That task is already completed."
            {:no_action, %{}, response}
        end
    end
  end

  defp execute_intent(user_id, :list_tasks, message, _entities) do
    {intent, metadata} = IntentClassifier.classify_with_metadata(message)

    tasks =
      cond do
        metadata[:filter] == :overdue ->
          Entries.list_overdue_tasks(user_id)

        metadata[:bucket] ->
          Entries.list_tasks(user_id, bucket: metadata[:bucket])

        metadata[:context] ->
          Entries.list_tasks(user_id, context: metadata[:context])

        true ->
          Entries.list_tasks(user_id)
      end

    response = ResponseGenerator.task_list(tasks, metadata)
    {:listed, %{tasks: tasks}, response}
  end

  defp execute_intent(user_id, :briefing, _message, _entities) do
    briefing = GTD.daily_review_data(user_id)
    response = ResponseGenerator.briefing(briefing)
    {:briefing_generated, %{briefing: briefing}, response}
  end

  defp execute_intent(user_id, :query, message, _entities) do
    alias Onelist.Searcher

    # Search using hybrid search (semantic + keyword)
    case Searcher.search(user_id, message, limit: 10, search_type: :hybrid) do
      {:ok, %{results: results}} when is_list(results) and length(results) > 0 ->
        response = ResponseGenerator.query_results(message, results)
        {:query_executed, %{search_results: results}, response}

      {:ok, %{results: []}} ->
        response = ResponseGenerator.no_results(message)
        {:query_executed, %{search_results: []}, response}

      {:ok, _} ->
        response = ResponseGenerator.no_results(message)
        {:query_executed, %{search_results: []}, response}

      {:error, reason} ->
        Logger.error("Search failed: #{inspect(reason)}")
        response = "I had trouble searching your entries. Please try again."
        {:error, %{error: reason}, response}
    end
  end

  defp execute_intent(user_id, :review, message, _entities) do
    {_intent, metadata} = IntentClassifier.classify_with_metadata(message)
    review_type = metadata[:review_type] || :daily

    case review_type do
      :daily ->
        data = GTD.daily_review_data(user_id)
        response = ResponseGenerator.daily_review(data)
        {:review_started, %{review_data: data}, response}

      :weekly ->
        data = GTD.weekly_review_data(user_id)
        response = ResponseGenerator.weekly_review(data)
        {:review_started, %{review_data: data}, response}

      _ ->
        {:no_action, %{}, "Let's start your review. Would you like daily or weekly?"}
    end
  end

  defp execute_intent(user_id, :chat, message, _entities) do
    # General chat - use Agent for rich LLM response with memory context
    alias Onelist.River.Agent
    alias Onelist.Accounts

    try do
      user = Accounts.get_user!(user_id)

      case Agent.chat(user, message, []) do
        {:ok, agent_response} ->
          {:chat, %{citations: agent_response.citations}, agent_response.message}

        {:error, _reason} ->
          # Fallback to simple response if Agent fails
          response = ResponseGenerator.chat_response()
          {:chat, %{}, response}
      end
    rescue
      Ecto.NoResultsError ->
        response = ResponseGenerator.chat_response()
        {:chat, %{}, response}
    end
  end

  # ============================================
  # EXTRACTION HELPERS
  # ============================================

  defp extract_task_title(message) do
    message
    |> String.replace(
      ~r/^(add\s+task[:\s]?|create\s+(a\s+)?task[:\s]?|remind\s+me\s+to\s+|i\s+need\s+to\s+|todo[:\s]?|don'?t\s+forget\s+to\s+)/i,
      ""
    )
    # Remove contexts
    |> String.replace(~r/@\w+/, "")
    # Remove "by <date>"
    |> String.replace(~r/\s+by\s+.+$/, "")
    |> String.trim()
  end

  defp extract_task_reference(message) do
    message
    |> String.replace(
      ~r/^(done\s+with\s+|finished\s+(with\s+)?|completed?\s+|mark\s+|set\s+)/i,
      ""
    )
    |> String.replace(~r/\s+(done|complete|as\s+done|as\s+complete)$/i, "")
    |> String.trim()
  end
end
