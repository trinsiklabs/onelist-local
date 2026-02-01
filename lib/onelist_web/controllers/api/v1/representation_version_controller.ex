defmodule OnelistWeb.Api.V1.RepresentationVersionController do
  @moduledoc """
  API controller for representation version history operations.

  Provides endpoints for viewing version history, retrieving content at
  specific versions, and reverting to previous versions.
  """
  use OnelistWeb, :controller

  alias Onelist.Entries
  alias Onelist.Repo

  action_fallback OnelistWeb.Api.V1.FallbackController

  @doc """
  Lists version history for a representation.

  GET /api/v1/entries/:entry_id/representations/:representation_id/versions

  Query parameters:
  - limit: Maximum number of versions to return (default: 50)
  """
  def index(conn, %{"entry_id" => entry_id, "representation_id" => rep_id} = params) do
    user = conn.assigns.current_user
    limit = parse_limit(params["limit"])

    with {:ok, _entry} <- get_user_entry(user, entry_id),
         {:ok, representation} <- get_representation(rep_id) do
      versions = Entries.list_representation_versions(representation, limit: limit)
      render(conn, :index, versions: versions)
    end
  end

  @doc """
  Shows content at a specific version.

  GET /api/v1/entries/:entry_id/representations/:representation_id/versions/:version
  """
  def show(conn, %{"entry_id" => entry_id, "representation_id" => rep_id, "id" => version_str}) do
    user = conn.assigns.current_user

    with {:ok, version} <- parse_version(version_str),
         {:ok, _entry} <- get_user_entry(user, entry_id),
         {:ok, representation} <- get_representation(rep_id),
         {:ok, content} <- Entries.get_content_at_version(representation, version) do
      render(conn, :show_content, content: content, version: version)
    end
  end

  @doc """
  Reverts a representation to a specific version.

  POST /api/v1/entries/:entry_id/representations/:representation_id/versions/:version_id/revert
  """
  def revert(conn, %{"entry_id" => entry_id, "representation_id" => rep_id, "version_id" => version_str}) do
    user = conn.assigns.current_user

    with {:ok, version} <- parse_version(version_str),
         {:ok, _entry} <- get_user_entry(user, entry_id),
         {:ok, representation} <- get_representation(rep_id),
         {:ok, updated_rep} <- Entries.revert_to_version(representation, version, user) do
      updated_rep = Repo.preload(updated_rep, :entry)
      render(conn, :show_representation, representation: updated_rep)
    end
  end

  # Private helpers

  defp get_user_entry(user, entry_id) do
    case Entries.get_user_entry(user, entry_id) do
      nil -> {:error, :not_found}
      entry -> {:ok, entry}
    end
  end

  defp get_representation(rep_id) do
    case Entries.get_representation(rep_id) do
      nil -> {:error, :not_found}
      rep -> {:ok, rep}
    end
  end

  defp parse_version(version_str) do
    case Integer.parse(version_str) do
      {version, ""} when version > 0 -> {:ok, version}
      _ -> {:error, :bad_request, "Invalid version number"}
    end
  end

  defp parse_limit(nil), do: 50
  defp parse_limit(limit_str) do
    case Integer.parse(limit_str) do
      {limit, ""} when limit > 0 and limit <= 100 -> limit
      _ -> 50
    end
  end
end
