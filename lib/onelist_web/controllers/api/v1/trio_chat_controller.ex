defmodule OnelistWeb.Api.V1.TrioChatController do
  @moduledoc """
  API endpoints for the Trio Chat system.

  Used by Keystone (Claude Code on Mac) to send/receive messages.
  Stream calls Onelist.Chat directly (internal).

  PLAN-048: Unified Chat Dashboard
  """
  use OnelistWeb, :controller

  alias Onelist.Chat

  @doc """
  Send a message to a channel.

  POST /api/v1/chat/send
  {
    "channel": "group" | "dm:key-stream" | etc,
    "sender": "key" | "stream" | "splntrb",
    "content": "message text"
  }
  """
  def send(conn, %{"channel" => channel, "sender" => sender, "content" => content}) do
    case Chat.send_message(channel, sender, content) do
      {:ok, message} ->
        json(conn, %{
          ok: true,
          message_id: message.id,
          channel: channel,
          inserted_at: message.inserted_at
        })

      {:error, :channel_not_found} ->
        conn
        |> put_status(404)
        |> json(%{ok: false, error: "channel_not_found"})

      {:error, :sender_not_in_channel} ->
        conn
        |> put_status(403)
        |> json(%{ok: false, error: "sender_not_in_channel"})

      {:error, changeset} ->
        conn
        |> put_status(400)
        |> json(%{ok: false, error: "invalid_message", details: format_errors(changeset)})
    end
  end

  @doc """
  Get messages from a channel.

  GET /api/v1/chat/messages?channel=group&limit=50&since=timestamp
  """
  def messages(conn, %{"channel" => channel} = params) do
    opts = [
      limit: parse_int(params["limit"], 50),
      since: parse_timestamp(params["since"]),
      before: parse_timestamp(params["before"])
    ] |> Enum.reject(fn {_, v} -> is_nil(v) end)

    case Chat.get_messages(channel, opts) do
      {:ok, messages} ->
        json(conn, %{
          ok: true,
          channel: channel,
          count: length(messages),
          messages: Enum.map(messages, &format_message/1)
        })

      {:error, :channel_not_found} ->
        conn
        |> put_status(404)
        |> json(%{ok: false, error: "channel_not_found"})
    end
  end

  @doc """
  Get unread messages for a participant.

  GET /api/v1/chat/unread?channel=dm:key-stream&participant=key
  """
  def unread(conn, %{"channel" => channel, "participant" => participant}) do
    case Chat.get_unread(channel, participant) do
      {:ok, messages} ->
        json(conn, %{
          ok: true,
          channel: channel,
          participant: participant,
          unread_count: length(messages),
          messages: Enum.map(messages, &format_message/1)
        })

      {:error, reason} ->
        conn
        |> put_status(400)
        |> json(%{ok: false, error: to_string(reason)})
    end
  end

  @doc """
  Mark messages as read.

  POST /api/v1/chat/mark_read
  {
    "channel": "dm:key-stream",
    "participant": "key",
    "message_id": "optional-uuid"
  }
  """
  def mark_read(conn, %{"channel" => channel, "participant" => participant} = params) do
    message_id = params["message_id"]

    case Chat.mark_read(channel, participant, message_id) do
      :ok ->
        json(conn, %{ok: true})

      {:error, reason} ->
        conn
        |> put_status(400)
        |> json(%{ok: false, error: to_string(reason)})
    end
  end

  @doc """
  List all channels (for initial load).

  GET /api/v1/chat/channels
  """
  def channels(conn, _params) do
    channels = Chat.list_channels()

    json(conn, %{
      ok: true,
      channels: Enum.map(channels, &format_channel/1)
    })
  end

  @doc """
  Get channel info with unread counts for a participant.

  GET /api/v1/chat/status?participant=key
  """
  def status(conn, %{"participant" => participant}) do
    channels = Chat.list_channels_for(participant)
    read_positions = Chat.get_read_positions(participant)

    channel_status =
      Enum.map(channels, fn channel ->
        last_read = Map.get(read_positions, channel.name)
        {:ok, unread} = Chat.unread_count(channel.name, participant)

        %{
          name: channel.name,
          type: channel.channel_type,
          participants: channel.participants,
          last_activity_at: channel.last_activity_at,
          last_read_at: last_read,
          unread_count: unread
        }
      end)

    json(conn, %{
      ok: true,
      participant: participant,
      channels: channel_status
    })
  end

  # ============================================
  # HELPERS
  # ============================================

  defp format_message(message) do
    %{
      id: message.id,
      sender: message.sender,
      content: message.content,
      message_type: message.message_type,
      inserted_at: message.inserted_at,
      edited_at: message.edited_at
    }
  end

  defp format_channel(channel) do
    %{
      id: channel.id,
      name: channel.name,
      type: channel.channel_type,
      participants: channel.participants,
      description: channel.description,
      last_activity_at: channel.last_activity_at
    }
  end

  defp format_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
  defp format_errors(error), do: error

  defp parse_int(nil, default), do: default
  defp parse_int(val, _default) when is_integer(val), do: val
  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_timestamp(nil), do: nil
  defp parse_timestamp(ts) when is_binary(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end
end
