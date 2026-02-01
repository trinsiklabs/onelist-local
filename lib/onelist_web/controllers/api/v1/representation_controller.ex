defmodule OnelistWeb.Api.V1.RepresentationController do
  @moduledoc """
  API controller for representation operations.
  """
  use OnelistWeb, :controller

  alias Onelist.Entries
  alias Onelist.Repo

  action_fallback OnelistWeb.Api.V1.FallbackController

  @doc """
  Lists representations for an entry.

  GET /api/v1/entries/:entry_id/representations
  """
  def index(conn, %{"entry_id" => entry_id}) do
    user = conn.assigns.current_user

    with {:ok, entry} <- get_user_entry(user, entry_id) do
      representations = Entries.list_representations(entry)
      render(conn, :index, representations: representations)
    end
  end

  @doc """
  Shows a single representation.

  GET /api/v1/entries/:entry_id/representations/:id
  """
  def show(conn, %{"entry_id" => entry_id, "id" => id}) do
    user = conn.assigns.current_user

    with {:ok, _entry} <- get_user_entry(user, entry_id),
         {:ok, representation} <- get_representation(id) do
      render(conn, :show, representation: representation)
    end
  end

  @doc """
  Updates a representation with version tracking.

  PUT /api/v1/entries/:entry_id/representations/:id
  """
  def update(conn, %{"entry_id" => entry_id, "id" => id, "representation" => rep_params}) do
    user = conn.assigns.current_user

    with {:ok, _entry} <- get_user_entry(user, entry_id),
         {:ok, representation} <- get_representation(id),
         {:ok, updated_rep} <- Entries.update_representation_with_version(representation, user, rep_params) do
      render(conn, :show, representation: updated_rep)
    end
  end

  def update(_conn, %{"entry_id" => _entry_id, "id" => _id}) do
    {:error, :bad_request, "Missing representation parameters"}
  end

  # Private helpers

  defp get_user_entry(user, entry_id) do
    case Entries.get_user_entry(user, entry_id) do
      nil -> {:error, :not_found}
      entry -> {:ok, entry}
    end
  end

  defp get_representation(id) do
    case Entries.get_representation(id) do
      nil -> {:error, :not_found}
      rep -> {:ok, Repo.preload(rep, :entry)}
    end
  end
end
