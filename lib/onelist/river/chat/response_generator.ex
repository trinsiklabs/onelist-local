defmodule Onelist.River.Chat.ResponseGenerator do
  @moduledoc """
  Generate natural language responses for River.
  """

  @doc """
  Generate response for task creation.
  """
  def task_created(task) do
    context_part =
      if task.metadata["gtd_context"] do
        " (#{task.metadata["gtd_context"]})"
      else
        ""
      end

    due_part =
      if task.metadata["due_date"] do
        ", due #{task.metadata["due_date"]}"
      else
        ""
      end

    "Got it! I've added '#{task.title}'#{context_part}#{due_part} to your inbox."
  end

  @doc """
  Generate response for task completion.
  """
  def task_completed(task) do
    "Done! '#{task.title}' is marked as complete. ✓"
  end

  @doc """
  Generate response for task list.
  """
  def task_list(tasks, metadata \\ %{}) do
    bucket = metadata[:bucket]
    context = metadata[:context]
    filter = metadata[:filter]

    header =
      cond do
        filter == :overdue -> "Here are your overdue tasks:"
        bucket == "inbox" -> "Here's your inbox:"
        bucket == "next_actions" -> "Here are your next actions:"
        bucket == "waiting_for" -> "Here's what you're waiting for:"
        bucket == "someday_maybe" -> "Here are your someday/maybe items:"
        context -> "Here are your #{context} tasks:"
        true -> "Here are your tasks:"
      end

    if Enum.empty?(tasks) do
      empty_message =
        cond do
          bucket == "inbox" -> "Your inbox is empty. Inbox zero! 🎉"
          bucket == "next_actions" -> "No next actions. Time to process your inbox!"
          filter == :overdue -> "No overdue tasks. You're on track!"
          true -> "No tasks found."
        end

      empty_message
    else
      task_lines =
        tasks
        |> Enum.with_index(1)
        |> Enum.map(fn {task, i} -> format_task_line(task, i) end)
        |> Enum.join("\n")

      "#{header}\n\n#{task_lines}"
    end
  end

  defp format_task_line(task, index) do
    context =
      if task.metadata["gtd_context"] do
        " #{task.metadata["gtd_context"]}"
      else
        ""
      end

    due =
      if task.metadata["due_date"] do
        " (due: #{task.metadata["due_date"]})"
      else
        ""
      end

    priority =
      case task.metadata["priority"] do
        p when p >= 2 -> " ⚡"
        p when p == 1 -> " !"
        _ -> ""
      end

    "#{index}. #{task.title}#{context}#{due}#{priority}"
  end

  @doc """
  Generate briefing response.
  """
  def briefing(data) do
    lines = ["Good morning! Here's your daily briefing:\n"]

    # Inbox
    inbox_line =
      if data.inbox_count > 0 do
        "📥 **Inbox:** #{data.inbox_count} item(s) to process"
      else
        "📥 **Inbox:** Empty ✓"
      end

    lines = lines ++ [inbox_line]

    # Overdue
    lines =
      if length(data.overdue) > 0 do
        overdue_titles = Enum.map(data.overdue, & &1.title) |> Enum.join(", ")
        lines ++ ["⚠️ **Overdue:** #{length(data.overdue)} - #{overdue_titles}"]
      else
        lines ++ ["✅ **Overdue:** None"]
      end

    # Due today
    lines =
      if length(data.due_today) > 0 do
        today_titles = Enum.map(data.due_today, & &1.title) |> Enum.join(", ")
        lines ++ ["📅 **Due Today:** #{length(data.due_today)} - #{today_titles}"]
      else
        lines ++ ["📅 **Due Today:** Nothing scheduled"]
      end

    Enum.join(lines, "\n")
  end

  @doc """
  Generate daily review intro.
  """
  def daily_review(data) do
    """
    Let's do your daily review! 📋

    Current status:
    • Inbox: #{data.inbox_count} items
    • Overdue: #{length(data.overdue)} items
    • Due today: #{length(data.due_today)} items
    • Next actions: #{data.next_actions_count}
    • Waiting for: #{data.waiting_for_count}

    Want to start processing your inbox, or review what's due?
    """
  end

  @doc """
  Generate weekly review intro.
  """
  def weekly_review(data) do
    """
    Time for your weekly review! 🗓️

    Week of #{data.week_of}

    Let's go through:
    1. Get inbox to zero (#{length(data.inbox_items)} items)
    2. Review next actions (#{length(data.next_actions)} items)
    3. Review waiting for (#{length(data.waiting_for)} items)
    4. Review someday/maybe (#{length(data.someday_maybe)} items)
    5. Review projects and goals

    Ready to start with your inbox?
    """
  end

  @doc """
  Generate response for query results.
  """
  def query_results(query, results) when is_list(results) do
    count = length(results)

    header =
      "I found #{count} relevant #{if count == 1, do: "entry", else: "entries"} for \"#{truncate(query, 50)}\":\n"

    result_lines =
      results
      |> Enum.with_index(1)
      |> Enum.map(fn {result, i} -> format_search_result(result, i) end)
      |> Enum.join("\n\n")

    footer = "\n\nWould you like me to tell you more about any of these?"

    header <> "\n" <> result_lines <> footer
  end

  defp format_search_result(result, index) do
    title = result[:title] || result[:entry_title] || "Untitled"
    content = result[:content] || result[:summary] || ""
    date = format_result_date(result[:inserted_at])
    public_id = result[:public_id] || result[:id]

    # Truncate content for preview
    preview = truncate(content, 150)

    ref = if public_id, do: " [ref:#{public_id}]", else: ""

    "[#{index}] **#{title}** (#{date})#{ref}\n#{preview}"
  end

  defp format_result_date(nil), do: "unknown date"
  defp format_result_date(datetime) when is_binary(datetime), do: datetime

  defp format_result_date(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%b %d, %Y")
  end

  defp format_result_date(%NaiveDateTime{} = datetime) do
    Calendar.strftime(datetime, "%b %d, %Y")
  end

  @doc """
  Generate response when no results found.
  """
  def no_results(query) do
    """
    I couldn't find any entries matching "#{truncate(query, 50)}".

    Try:
    • Using different keywords
    • Checking for typos
    • Asking in a different way

    Or if this is something new, would you like me to add it to your inbox?
    """
  end

  defp truncate(text, max_length) when is_binary(text) do
    if String.length(text) > max_length do
      String.slice(text, 0, max_length) <> "..."
    else
      text
    end
  end

  defp truncate(_, _), do: ""

  @doc """
  Generate generic chat response.
  """
  def chat_response do
    responses = [
      "I'm here to help! You can ask me to add tasks, show your inbox, or give you a briefing.",
      "How can I help you today? Try 'add task: ...' or 'what's on my agenda?'",
      "I'm River, your assistant. I can help with tasks, reminders, and finding information.",
      "Hello! I can help you manage tasks and search your notes. What would you like to do?"
    ]

    Enum.random(responses)
  end

  @doc """
  Generate error response.
  """
  def error(reason) do
    case reason do
      :not_found -> "I couldn't find what you're looking for."
      :already_completed -> "That task is already marked as complete."
      _ -> "Something went wrong. Please try again."
    end
  end
end
