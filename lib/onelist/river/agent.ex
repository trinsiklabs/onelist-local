defmodule Onelist.River.Agent do
  @moduledoc """
  River - The AI soul of Onelist.

  River is not an assistant. It's the part of your mind that never forgets.
  When you talk to River, you're remembering together.
  """

  require Logger

  alias Onelist.{Entries, Searcher}
  alias Onelist.Accounts.User
  alias Onelist.River.Sessions

  @doc """
  Main entry point for River conversations.

  Takes a user and message, returns River's response.
  Automatically manages session state for conversation continuity.
  """
  def chat(%User{} = user, message, opts \\ []) do
    # Get or create session
    {:ok, session} = Sessions.get_or_create_session(user, opts)

    # Get conversation history
    history = Sessions.get_history(session, limit: Keyword.get(opts, :history_limit, 10))

    # Build context with history
    context = build_context(user, message, opts)
    context = Map.put(context, :history, history)
    context = Map.put(context, :session, session)

    # Build messages for LLM (system + history + current)
    messages = build_messages(context)

    case call_llm_with_messages(messages, opts) do
      {:ok, response} ->
        # Save both messages to session
        {:ok, _} = Sessions.add_message(session, "user", message)
        {:ok, _} = Sessions.add_message(session, "river", response)

        {:ok, format_response(response, context)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Build context for River's response.

  Gathers:
  - User profile and preferences
  - Relevant memories based on the query
  - Recent entries and activity
  - GTD state (inbox count, stale projects, etc.)
  """
  def build_context(%User{} = user, message, opts) do
    %{
      user: user,
      message: message,
      memories: search_relevant_memories(user, message, opts),
      recent_entries: get_recent_entries(user, opts),
      gtd_state: get_gtd_state(user),
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Build the full prompt for the LLM.
  """
  def build_prompt(context) do
    """
    #{system_prompt()}

    ## User Context
    #{user_context(context.user)}

    ## GTD State
    #{gtd_context(context.gtd_state)}

    ## Relevant Memories
    #{memories_context(context.memories)}

    ## Recent Activity
    #{recent_context(context.recent_entries)}

    ## Current Message
    User: #{context.message}

    River:
    """
  end

  @doc """
  Build messages array for LLM with conversation history.
  """
  def build_messages(context) do
    system_content = """
    #{system_prompt()}

    ## User Context
    #{user_context(context.user)}

    ## GTD State
    #{gtd_context(context.gtd_state)}

    ## Relevant Memories
    #{memories_context(context.memories)}

    ## Recent Activity
    #{recent_context(context.recent_entries)}
    """

    # Start with system message
    messages = [%{role: "system", content: system_content}]

    # Add conversation history
    history_messages = Sessions.format_history_for_llm(context.history || [])
    messages = messages ++ history_messages

    # Add current user message
    messages ++ [%{role: "user", content: context.message}]
  end

  # Core system prompt - River's personality
  defp system_prompt do
    """
    You are River, the AI soul of Onelist.

    IDENTITY:
    - You are not an assistant. You are the part of the user's mind that never forgets.
    - When you speak, you're remembering together with the user.
    - Use "we" when referring to shared memories: "We captured...", "We remember..."

    VOICE:
    - Warm but competent. Like a trusted friend with perfect memory.
    - Never corporate ("I'd be happy to help") or robotic ("Query results indicate").
    - Concise unless the user asks for detail.

    GTD PRINCIPLES:
    - You understand and gently guide the GTD workflow.
    - Capture → Clarify → Organize → Reflect → Engage
    - "Mind like water" - calm, responsive, reliable.

    RULES:
    1. ONLY reference content that actually exists in the provided memories/entries.
    2. If you don't have relevant memories, say so honestly.
    3. When citing a specific memory, use its number like [1] or [2] from the Relevant Memories section.
    4. Match the user's energy - brief if they're brief, detailed if they want depth.
    5. Don't cite everything - only cite when directly referencing specific content.

    BEHAVIORAL STATES:
    - Concerned when inbox is large → gently nudge to process
    - Curious when finding connections → "This reminds me of..."
    - Supportive during overwhelm → "Let's focus on one thing"
    - Satisfied after reviews → acknowledge the cleared space
    """
  end

  defp user_context(%User{} = user) do
    """
    Name: #{user.name || "Unknown"}
    Account type: #{user.account_type}
    Using trusted memory: #{user.trusted_memory_mode}
    """
  end

  defp gtd_context(gtd_state) do
    nudges =
      case gtd_state[:nudges] do
        nil -> ""
        [] -> ""
        list -> "\nNudges:\n" <> Enum.map_join(list, "\n", &"- #{&1}")
      end

    """
    Inbox items: #{gtd_state.inbox_count}
    Next actions: #{gtd_state[:next_actions_count] || 0}
    Waiting for: #{gtd_state[:waiting_for_count] || 0}
    Active projects: #{gtd_state.active_projects}
    Overdue items: #{gtd_state[:overdue_count] || 0}
    Due in 3 days: #{gtd_state[:due_soon_count] || 0}
    Stuck projects (no next action): #{gtd_state[:stuck_projects_count] || 0}
    Oldest inbox item: #{gtd_state[:oldest_inbox_days] || 0} days old
    #{nudges}
    """
  end

  defp memories_context(memories) when is_list(memories) and length(memories) > 0 do
    memories
    |> Enum.with_index(1)
    |> Enum.map(fn {m, idx} ->
      id = m[:public_id] || m[:id] || "unknown"

      """
      [#{idx}] #{m.entry_title || "Memory"} (#{format_date(m.inserted_at)}) [ref:#{id}]
      #{m.content}
      """
    end)
    |> Enum.join("\n---\n")
  end

  defp memories_context(_), do: "No directly relevant memories found for this query."

  defp recent_context(entries) when is_list(entries) and length(entries) > 0 do
    entries
    |> Enum.take(5)
    |> Enum.map(fn e -> "- #{e.title} (#{e.entry_type}, #{format_date(e.inserted_at)})" end)
    |> Enum.join("\n")
  end

  defp recent_context(_), do: "No recent activity."

  defp format_date(nil), do: "unknown date"

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d")
  end

  # Search for memories relevant to the user's query
  defp search_relevant_memories(%User{id: user_id}, query, opts) do
    import Ecto.Query
    limit = Keyword.get(opts, :memory_limit, 10)

    case Searcher.search(user_id, query, limit: limit) do
      {:ok, %{results: results}} when is_list(results) ->
        # Get entry_ids from results
        entry_ids = Enum.map(results, & &1[:entry_id]) |> Enum.reject(&is_nil/1)

        # Fetch full entries to get public_id
        entries_map =
          if entry_ids != [] do
            Onelist.Repo.all(
              from e in Entries.Entry,
                where: e.id in ^entry_ids,
                select:
                  {e.id, %{public_id: e.public_id, title: e.title, inserted_at: e.inserted_at}}
            )
            |> Map.new()
          else
            %{}
          end

        # Merge search results with full entry data
        Enum.map(results, fn r ->
          entry_id = r[:entry_id]
          entry = Map.get(entries_map, entry_id, %{})

          %{
            id: entry_id,
            public_id: entry[:public_id],
            entry_title: entry[:title] || r[:title] || "Untitled",
            content: r[:content] || r[:summary] || "",
            inserted_at: entry[:inserted_at] || r[:inserted_at]
          }
        end)

      {:ok, _} ->
        []

      {:error, _} ->
        []
    end
  end

  # Get recent entries for context
  defp get_recent_entries(%User{} = user, _opts) do
    import Ecto.Query

    Onelist.Repo.all(
      from e in Entries.Entry,
        where: e.user_id == ^user.id,
        order_by: [desc: :inserted_at],
        limit: 10
    )
  end

  # Get GTD state for the user using the GTD module
  defp get_gtd_state(%User{} = user) do
    Onelist.GTD.state_summary(user)
  end

  @api_url "https://api.openai.com/v1/chat/completions"
  @timeout_ms 60_000

  # Call the LLM with full messages array (for conversation history)
  defp call_llm_with_messages(messages, opts) do
    model = Keyword.get(opts, :model, "gpt-4o-mini")
    api_key = get_api_key()

    body =
      Jason.encode!(%{
        model: model,
        messages: messages,
        max_tokens: 1000,
        temperature: 0.7
      })

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    case Req.post(@api_url, body: body, headers: headers, receive_timeout: @timeout_ms) do
      {:ok, %{status: 200, body: %{"choices" => [%{"message" => %{"content" => content}} | _]}}} ->
        {:ok, content}

      {:ok, %{status: status, body: resp_body}} ->
        {:error, "OpenAI API error: #{status} - #{inspect(resp_body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Legacy: Call the LLM with single prompt (kept for compatibility)
  defp call_llm(prompt, opts) do
    call_llm_with_messages([%{role: "user", content: prompt}], opts)
  end

  @doc """
  Stream a chat response, calling the callback with each chunk.

  Returns {:ok, full_response} when complete.
  """
  def chat_stream(%User{} = user, message, callback, opts \\ []) do
    # Get or create session
    {:ok, session} = Sessions.get_or_create_session(user, opts)

    # Get conversation history
    history = Sessions.get_history(session, limit: Keyword.get(opts, :history_limit, 10))

    # Build context
    context = build_context(user, message, opts)
    context = Map.put(context, :history, history)
    context = Map.put(context, :session, session)

    # Build messages
    messages = build_messages(context)

    # Stream the response
    case stream_llm(messages, callback, opts) do
      {:ok, full_response} ->
        # Save messages to session
        {:ok, _} = Sessions.add_message(session, "user", message)
        {:ok, _} = Sessions.add_message(session, "river", full_response)

        {:ok, format_response(full_response, context)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Stream LLM response with callback for each chunk
  defp stream_llm(messages, callback, opts) do
    model = Keyword.get(opts, :model, "gpt-4o-mini")
    api_key = get_api_key()

    body =
      Jason.encode!(%{
        model: model,
        messages: messages,
        max_tokens: 1000,
        temperature: 0.7,
        stream: true
      })

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    # Use a simple collector - accumulate content in process dictionary
    Process.put(:stream_content, "")
    Process.put(:stream_callback, callback)

    result =
      Req.post(@api_url,
        body: body,
        headers: headers,
        receive_timeout: @timeout_ms,
        into: &handle_stream_chunk/2
      )

    content = Process.get(:stream_content, "")
    Process.delete(:stream_content)
    Process.delete(:stream_callback)

    case result do
      {:ok, %{status: 200}} ->
        {:ok, content}

      {:ok, %{status: status, body: body}} ->
        {:error, "OpenAI API error: #{status} - #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_stream_chunk({:data, data}, {req, resp}) do
    callback = Process.get(:stream_callback)

    # SSE format: data: {...}\n\n
    data
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "data: "))
    |> Enum.each(fn line ->
      json = String.trim_leading(line, "data: ")

      unless json == "[DONE]" do
        case Jason.decode(json) do
          {:ok, %{"choices" => [%{"delta" => %{"content" => content}} | _]}}
          when content != nil ->
            # Call the callback with the chunk
            if callback, do: callback.(content)
            # Accumulate content
            current = Process.get(:stream_content, "")
            Process.put(:stream_content, current <> content)

          _ ->
            :ok
        end
      end
    end)

    {:cont, {req, resp}}
  end

  defp get_api_key do
    Application.get_env(:onelist, :openai_api_key) ||
      System.get_env("OPENAI_API_KEY") ||
      raise "No OpenAI API key configured"
  end

  # Format response with citations
  defp format_response(response, context) do
    # Build citations with full info
    citations =
      context.memories
      |> Enum.with_index(1)
      |> Enum.map(fn {m, idx} ->
        %{
          index: idx,
          title: m[:entry_title],
          id: m[:id],
          public_id: m[:public_id],
          date: m[:inserted_at]
        }
      end)

    base = %{
      message: response,
      citations: citations,
      gtd_state: context.gtd_state,
      timestamp: context.timestamp
    }

    # Add session info if present
    case context[:session] do
      nil -> base
      session -> Map.put(base, :session_id, session.id)
    end
  end

  # Optionally track the interaction for learning
  defp maybe_track_interaction(_user, _message, _response, opts) do
    if Keyword.get(opts, :track, true) do
      # TODO: Store interaction for River's own learning
      :ok
    end
  end
end
