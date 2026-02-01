defmodule OnelistWeb.Api.V1.TagController do
  @moduledoc """
  API controller for Tag CRUD operations.
  """
  use OnelistWeb, :controller

  alias Onelist.Tags

  action_fallback OnelistWeb.Api.V1.FallbackController

  @doc """
  Lists all tags for the authenticated user with entry counts.
  """
  def index(conn, _params) do
    user = conn.assigns.current_user
    tags = Tags.list_user_tags_with_counts(user)
    render(conn, :index, tags: tags)
  end

  @doc """
  Shows a single tag.
  """
  def show(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Tags.get_user_tag(user, id) do
      nil ->
        {:error, :not_found}

      tag ->
        render(conn, :show, tag: tag)
    end
  end

  @doc """
  Creates a new tag for the authenticated user.

  Expected params:
  - tag.name: Tag name (required)
  """
  def create(conn, %{"tag" => tag_params}) do
    user = conn.assigns.current_user

    case Tags.create_tag(user, tag_params) do
      {:ok, tag} ->
        conn
        |> put_status(:created)
        |> put_resp_header("location", ~p"/api/v1/tags/#{tag.id}")
        |> render(:create, tag: tag)

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def create(_conn, _params) do
    {:error, :bad_request, "Missing tag parameters"}
  end

  @doc """
  Updates an existing tag.

  Expected params:
  - tag.name: Tag name (optional)
  """
  def update(conn, %{"id" => id, "tag" => tag_params}) do
    user = conn.assigns.current_user

    case Tags.get_user_tag(user, id) do
      nil ->
        {:error, :not_found}

      tag ->
        case Tags.update_tag(tag, tag_params) do
          {:ok, updated_tag} ->
            render(conn, :update, tag: updated_tag)

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  def update(_conn, %{"id" => _id}) do
    {:error, :bad_request, "Missing tag parameters"}
  end

  @doc """
  Deletes a tag.
  """
  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Tags.get_user_tag(user, id) do
      nil ->
        {:error, :not_found}

      tag ->
        case Tags.delete_tag(tag) do
          {:ok, _tag} ->
            send_resp(conn, :no_content, "")

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end
end
