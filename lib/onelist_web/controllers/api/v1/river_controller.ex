defmodule OnelistWeb.Api.V1.RiverController do
  use OnelistWeb, :controller

  alias Onelist.River.Agent
  alias Onelist.River.Chat

  @doc """
  POST /api/river/chat

  Body:
    {
      "message": "What was that idea I had about habit tracking?",
      "options": {
        "memory_limit": 10,
        "model": "gpt-4o-mini"
      }
    }
    
  Response:
    {
      "message": "We have a few threads on habit tracking...",
      "memories_used": ["abc123", "def456"],
      "gtd_state": {
        "inbox_count": 5,
        "active_projects": 3
      }
    }
  """
  def chat(conn, %{"message" => message} = params) do
    user = conn.assigns.current_user

    opts = parse_options(params["options"] || %{})
    opts = Keyword.put(opts, :conversation_id, params["conversation_id"])

    # Use Chat.process for intent detection + action execution
    # Falls back to Agent.chat for conversational responses
    case Chat.process(user.id, message, opts) do
      {:ok, response} ->
        conn
        |> put_status(:ok)
        |> json(%{
          message: response.message,
          intent: response.intent,
          action_taken: response.action_taken,
          citations: response[:citations] || [],
          gtd_state: response.gtd_state,
          session_id: response.conversation_id
        })

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to process: #{inspect(reason)}"})
    end
  end

  @doc """
  GET /api/river/sessions

  Returns recent River sessions for the user.
  """
  def sessions(conn, params) do
    user = conn.assigns.current_user
    limit = params["limit"] || 10

    sessions = Onelist.River.Sessions.list_sessions(user, limit: limit)

    conn
    |> put_status(:ok)
    |> json(%{
      sessions:
        Enum.map(sessions, fn s ->
          %{
            id: s.id,
            started_at: s.started_at,
            last_message_at: s.last_message_at,
            message_count: s.message_count
          }
        end)
    })
  end

  @doc """
  GET /api/river/sessions/:id

  Returns a specific session with its messages.
  """
  def show_session(conn, %{"id" => session_id}) do
    user = conn.assigns.current_user

    case get_user_session(user, session_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Session not found"})

      session ->
        messages = Onelist.River.Sessions.get_history(session, limit: 100)

        conn
        |> put_status(:ok)
        |> json(%{
          session: %{
            id: session.id,
            started_at: session.started_at,
            last_message_at: session.last_message_at,
            message_count: session.message_count
          },
          messages:
            Enum.map(messages, fn m ->
              %{
                id: m.id,
                role: m.role,
                content: m.content,
                timestamp: m.inserted_at
              }
            end)
        })
    end
  end

  defp get_user_session(user, session_id) do
    import Ecto.Query

    Onelist.Repo.one(
      from s in Onelist.River.Session,
        where: s.id == ^session_id,
        where: s.user_id == ^user.id
    )
  end

  @doc """
  POST /api/river/weekly-review/complete

  Mark the weekly review as completed.
  """
  def complete_review(conn, _params) do
    user = conn.assigns.current_user

    case Onelist.GTD.complete_weekly_review(user) do
      {:ok, updated_user} ->
        conn
        |> put_status(:ok)
        |> json(%{
          message: "Weekly review completed!",
          last_review: updated_user.last_weekly_review
        })

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to complete review"})
    end
  end

  @doc """
  POST /api/river/sessions/:id/close

  Close a session and archive it as an entry.
  """
  def close_session(conn, %{"id" => session_id}) do
    user = conn.assigns.current_user

    case get_user_session(user, session_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Session not found"})

      session ->
        case Onelist.River.Sessions.close_session(session) do
          {:ok, entry} ->
            conn
            |> put_status(:ok)
            |> json(%{
              message: "Session closed and archived",
              entry_id: entry.public_id
            })

          {:error, reason} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: inspect(reason)})
        end
    end
  end

  @doc """
  GET /api/river/gtd-state

  Get full GTD state for weekly review.
  """
  def gtd_state(conn, _params) do
    user = conn.assigns.current_user
    state = Onelist.GTD.weekly_review_state(user)

    conn
    |> put_status(:ok)
    |> json(state)
  end

  @doc """
  POST /api/river/chat/stream

  Stream River's response as Server-Sent Events.

  Response format:
    event: chunk
    data: {"content": "word"}
    
    event: done
    data: {"citations": [...], "gtd_state": {...}}
  """
  def chat_stream(conn, %{"message" => message} = params) do
    user = conn.assigns.current_user
    opts = parse_options(params["options"] || %{})

    # Set up SSE response
    conn =
      conn
      |> put_resp_content_type("text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("connection", "keep-alive")
      |> send_chunked(200)

    # Callback sends each chunk as SSE
    callback = fn content ->
      chunk_data = Jason.encode!(%{content: content})
      chunk(conn, "event: chunk\ndata: #{chunk_data}\n\n")
    end

    # Stream the response
    case Agent.chat_stream(user, message, callback, opts) do
      {:ok, response} ->
        # Send final event with metadata
        done_data =
          Jason.encode!(%{
            citations: response.citations,
            gtd_state: response.gtd_state,
            session_id: response[:session_id]
          })

        chunk(conn, "event: done\ndata: #{done_data}\n\n")

      {:error, reason} ->
        error_data = Jason.encode!(%{error: inspect(reason)})
        chunk(conn, "event: error\ndata: #{error_data}\n\n")
    end

    conn
  end

  @doc """
  GET /api/river/context

  Returns River's current understanding of the user's state.
  Useful for UI to show inbox count, nudges, etc.
  """
  def context(conn, _params) do
    user = conn.assigns.current_user

    context = Agent.build_context(user, "", [])

    conn
    |> put_status(:ok)
    |> json(%{
      gtd_state: context.gtd_state,
      recent_entries:
        Enum.map(context.recent_entries, fn e ->
          %{
            id: e.public_id,
            title: e.title,
            type: e.entry_type,
            created: e.inserted_at
          }
        end)
    })
  end

  @doc """
  POST /api/river/capture

  Quick capture through River.
  River acknowledges and can optionally clarify.

  Body:
    {
      "content": "Idea about using graphs for memory",
      "clarify": true
    }
  """
  def capture(conn, %{"content" => content} = params) do
    user = conn.assigns.current_user
    clarify = params["clarify"] || false

    # Create the inbox entry
    {:ok, entry} =
      Onelist.Entries.create_entry(user, %{
        title: generate_title(content),
        entry_type: "note",
        source_type: "river_capture",
        metadata: %{status: "inbox"}
      })

    {:ok, _} =
      Onelist.Entries.add_representation(entry, %{
        type: "plaintext",
        content: content
      })

    response =
      if clarify do
        # Ask River to help clarify
        {:ok, clarification} =
          Agent.chat(
            user,
            "I just captured this to inbox: '#{content}'. Help me clarify: What's the next action? Is this a project or single task? Any relevant context from our memories?",
            []
          )

        %{
          captured: true,
          entry_id: entry.public_id,
          clarification: clarification.message
        }
      else
        %{
          captured: true,
          entry_id: entry.public_id,
          message: "Got it, added to inbox."
        }
      end

    conn
    |> put_status(:created)
    |> json(response)
  end

  # Generate a title from content (first line or truncated)
  defp generate_title(content) do
    content
    |> String.split("\n")
    |> List.first()
    |> String.slice(0, 100)
    |> then(fn t -> if String.length(t) < String.length(content), do: t <> "...", else: t end)
  end

  defp parse_options(opts) when is_map(opts) do
    [
      memory_limit: opts["memory_limit"] || 10,
      recent_limit: opts["recent_limit"] || 10,
      model: opts["model"] || "gpt-4o-mini",
      track: opts["track"] != false
    ]
  end

  # ============================================
  # CONVERSATIONS
  # ============================================

  @doc """
  GET /api/v1/river/conversations

  List user's River conversations.
  """
  def list_conversations(conn, params) do
    user = conn.assigns.current_user
    limit = params["limit"] || 20

    conversations = Onelist.River.list_conversations(user.id, limit: limit)

    conn
    |> put_status(:ok)
    |> json(%{
      conversations: Enum.map(conversations, &format_conversation/1),
      count: length(conversations)
    })
  end

  @doc """
  GET /api/v1/river/conversations/:id

  Get a specific conversation with messages.
  """
  def show_conversation(conn, %{"id" => conversation_id}) do
    user = conn.assigns.current_user

    case Onelist.Entries.get_entry(conversation_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Conversation not found"})

      conversation ->
        if conversation.user_id != user.id do
          conn
          |> put_status(:not_found)
          |> json(%{error: "Conversation not found"})
        else
          messages = Onelist.River.Entries.get_conversation_messages(conversation_id)

          conn
          |> put_status(:ok)
          |> json(%{
            conversation: format_conversation(conversation),
            messages: Enum.map(messages, &format_message/1)
          })
        end
    end
  end

  defp format_conversation(conv) do
    %{
      id: conv.id,
      title: conv.title,
      created_at: conv.inserted_at,
      updated_at: conv.updated_at,
      message_count: conv.metadata["message_count"] || 0
    }
  end

  defp format_message(msg) do
    # msg is a Representation with type "chat_message"
    %{
      id: msg.id,
      role: msg.metadata["role"],
      content: msg.content,
      timestamp: msg.inserted_at
    }
  end

  # ============================================
  # TASKS
  # ============================================

  @doc """
  GET /api/v1/river/tasks

  List user's tasks with optional filters.
  """
  def list_tasks(conn, params) do
    user = conn.assigns.current_user

    opts = []
    opts = if params["bucket"], do: Keyword.put(opts, :bucket, params["bucket"]), else: opts
    opts = if params["context"], do: Keyword.put(opts, :context, params["context"]), else: opts
    opts = if params["status"], do: Keyword.put(opts, :status, params["status"]), else: opts

    tasks = Onelist.River.list_tasks(user.id, opts)

    conn
    |> put_status(:ok)
    |> json(%{
      tasks: Enum.map(tasks, &format_task/1),
      count: length(tasks)
    })
  end

  @doc """
  POST /api/v1/river/tasks

  Create a new task.
  """
  @valid_buckets ~w(inbox next_actions waiting_for someday_maybe)

  def create_task(conn, params) do
    user = conn.assigns.current_user
    title = params["title"]
    bucket = params["bucket"] || "inbox"

    # Validate required fields
    cond do
      is_nil(title) or title == "" ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{title: ["can't be blank"]}})

      bucket not in @valid_buckets ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{bucket: ["must be one of: #{Enum.join(@valid_buckets, ", ")}"]}})

      true ->
        attrs =
          %{
            title: title,
            gtd_bucket: bucket,
            gtd_context: params["context"],
            priority: params["priority"],
            due_date: params["due_date"],
            due_time: params["due_time"]
          }
          |> Enum.reject(fn {_k, v} -> is_nil(v) end)
          |> Map.new()

        case Onelist.River.create_task(user.id, attrs) do
          {:ok, task} ->
            conn
            |> put_status(:created)
            |> json(%{task: format_task(task)})

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{errors: format_errors(changeset)})
        end
    end
  end

  @doc """
  GET /api/v1/river/tasks/:id

  Get a specific task.
  """
  def show_task(conn, %{"id" => task_id}) do
    user = conn.assigns.current_user

    case Onelist.River.get_task(task_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Task not found"})

      task ->
        if task.user_id != user.id do
          conn
          |> put_status(:not_found)
          |> json(%{error: "Task not found"})
        else
          conn
          |> put_status(:ok)
          |> json(%{task: format_task(task)})
        end
    end
  end

  @doc """
  PATCH /api/v1/river/tasks/:id

  Update a task.
  """
  def update_task(conn, %{"id" => task_id} = params) do
    user = conn.assigns.current_user

    case Onelist.River.get_task(task_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Task not found"})

      task ->
        if task.user_id != user.id do
          conn
          |> put_status(:not_found)
          |> json(%{error: "Task not found"})
        else
          attrs =
            params
            |> Map.take(["title", "bucket", "context", "priority", "due_date", "due_time"])
            |> Enum.reject(fn {_k, v} -> is_nil(v) end)
            |> Map.new()

          case Onelist.River.update_task(task_id, attrs) do
            {:ok, updated} ->
              conn
              |> put_status(:ok)
              |> json(%{task: format_task(updated)})

            {:error, changeset} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{errors: format_errors(changeset)})
          end
        end
    end
  end

  @doc """
  POST /api/v1/river/tasks/:id/complete

  Mark a task as complete.
  """
  def complete_task(conn, %{"id" => task_id}) do
    user = conn.assigns.current_user

    case Onelist.River.get_task(task_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Task not found"})

      task ->
        if task.user_id != user.id do
          conn
          |> put_status(:not_found)
          |> json(%{error: "Task not found"})
        else
          case Onelist.River.complete_task(task_id) do
            {:ok, completed} ->
              conn
              |> put_status(:ok)
              |> json(%{task: format_task(completed), message: "Task completed!"})

            {:error, :already_completed} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{error: "Task is already completed"})

            {:error, reason} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{error: inspect(reason)})
          end
        end
    end
  end

  defp format_task(task) do
    %{
      id: task.id,
      public_id: task.public_id,
      title: task.title,
      bucket: task.metadata["gtd_bucket"] || "inbox",
      context: task.metadata["gtd_context"],
      priority: task.metadata["priority"],
      due_date: task.metadata["due_date"],
      due_time: task.metadata["due_time"],
      status: task.metadata["status"] || "pending",
      completed_at: task.metadata["completed_at"],
      created_at: task.inserted_at,
      updated_at: task.updated_at
    }
  end

  defp format_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp format_errors(error), do: %{base: [inspect(error)]}

  # ============================================
  # BRIEFINGS
  # ============================================

  @doc """
  GET /api/v1/river/briefing

  Get a briefing (daily or weekly).
  """
  def briefing(conn, params) do
    user = conn.assigns.current_user
    type = params["type"] || "daily"

    case type do
      "daily" ->
        data = Onelist.River.GTD.daily_review_data(user.id)

        conn
        |> put_status(:ok)
        |> json(format_daily_briefing(data))

      "weekly" ->
        data = Onelist.River.GTD.weekly_review_data(user.id)

        conn
        |> put_status(:ok)
        |> json(format_weekly_briefing(data))

      _ ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid briefing type. Use 'daily' or 'weekly'."})
    end
  end

  defp format_daily_briefing(data) do
    %{
      type: "daily",
      inbox_count: data.inbox_count,
      next_actions_count: data[:next_actions_count] || 0,
      waiting_for_count: data[:waiting_for_count] || 0,
      overdue: Enum.map(data.overdue, &format_task/1),
      due_today: Enum.map(data.due_today, &format_task/1)
    }
  end

  defp format_weekly_briefing(data) do
    %{
      type: "weekly",
      week_of: data.week_of,
      inbox_items: Enum.map(data[:inbox_items] || [], &format_task/1),
      next_actions: Enum.map(data[:next_actions] || [], &format_task/1),
      waiting_for: Enum.map(data[:waiting_for] || [], &format_task/1),
      someday_maybe: Enum.map(data[:someday_maybe] || [], &format_task/1)
    }
  end
end
