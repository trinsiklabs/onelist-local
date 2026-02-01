defmodule OnelistWeb.Api.V1.EntryTagController do
  @moduledoc """
  API controller for managing tags on entries.
  """
  use OnelistWeb, :controller

  alias Onelist.Entries
  alias Onelist.Tags
  alias OnelistWeb.Api.V1.TagJSON

  action_fallback OnelistWeb.Api.V1.FallbackController

  @doc """
  Lists all tags for an entry.
  """
  def index(conn, %{"entry_id" => entry_id}) do
    user = conn.assigns.current_user

    case Entries.get_user_entry(user, entry_id) do
      nil ->
        {:error, :not_found}

      entry ->
        tags = Tags.list_entry_tags(entry)

        conn
        |> put_view(json: TagJSON)
        |> render(:index, tags: Enum.map(tags, fn tag -> {tag, 0} end))
    end
  end

  @doc """
  Adds a tag to an entry.

  Accepts either:
  - tag_id: ID of an existing tag
  - tag_name: Name of a tag (will be created if it doesn't exist)
  """
  def create(conn, %{"entry_id" => entry_id} = params) do
    user = conn.assigns.current_user

    with {:ok, entry} <- get_user_entry(user, entry_id),
         {:ok, tag} <- resolve_tag(user, params),
         {:ok, _entry_tag} <- Tags.add_tag_to_entry(entry, tag) do
      conn
      |> put_status(:created)
      |> put_view(json: TagJSON)
      |> render(:show, tag: tag)
    end
  end

  @doc """
  Removes a tag from an entry.
  """
  def delete(conn, %{"entry_id" => entry_id, "id" => tag_id}) do
    user = conn.assigns.current_user

    with {:ok, entry} <- get_user_entry(user, entry_id),
         {:ok, tag} <- get_user_tag(user, tag_id),
         {:ok, _result} <- Tags.remove_tag_from_entry(entry, tag) do
      send_resp(conn, :no_content, "")
    end
  end

  # Private helpers

  defp get_user_entry(user, entry_id) do
    case Entries.get_user_entry(user, entry_id) do
      nil -> {:error, :not_found}
      entry -> {:ok, entry}
    end
  end

  defp get_user_tag(user, tag_id) do
    case Tags.get_user_tag(user, tag_id) do
      nil -> {:error, :not_found}
      tag -> {:ok, tag}
    end
  end

  defp resolve_tag(user, %{"tag_id" => tag_id}) when is_binary(tag_id) do
    get_user_tag(user, tag_id)
  end

  defp resolve_tag(user, %{"tag_name" => tag_name}) when is_binary(tag_name) do
    Tags.get_or_create_tag(user, tag_name)
  end

  defp resolve_tag(_user, _params) do
    {:error, :bad_request, "Must provide either tag_id or tag_name"}
  end
end
