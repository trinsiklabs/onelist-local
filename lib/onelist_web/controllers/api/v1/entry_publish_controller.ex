defmodule OnelistWeb.Api.V1.EntryPublishController do
  @moduledoc """
  API controller for publishing and unpublishing entries.
  """
  use OnelistWeb, :controller

  alias Onelist.Entries

  action_fallback OnelistWeb.Api.V1.FallbackController

  @doc """
  Publishes an entry, making it publicly accessible.

  Returns the public URL and list of assets that were published.
  """
  def publish(conn, %{"entry_id" => entry_id}) do
    user = conn.assigns.current_user

    with {:ok, entry} <- get_user_entry(user, entry_id),
         {:ok, _} <- ensure_username(user),
         {:ok, _} <- ensure_has_content(entry),
         {:ok, published_entry} <- Entries.make_entry_public(entry) do
      public_url = Entries.public_entry_url(published_entry)
      assets = list_entry_assets(published_entry)

      render(conn, :publish,
        public_url: public_url,
        assets_published: assets
      )
    end
  end

  @doc """
  Unpublishes an entry, making it private again.

  Returns the list of assets that were removed from public access.
  """
  def unpublish(conn, %{"entry_id" => entry_id}) do
    user = conn.assigns.current_user

    with {:ok, entry} <- get_user_entry(user, entry_id),
         assets <- list_entry_assets(entry),
         {:ok, _private_entry} <- Entries.make_entry_private(entry) do
      render(conn, :unpublish, assets_removed: assets)
    end
  end

  @doc """
  Returns a preview of what will happen when publishing an entry.

  Shows the public URL that will be used and lists assets with their sizes.
  """
  def preview(conn, %{"entry_id" => entry_id}) do
    user = conn.assigns.current_user

    with {:ok, entry} <- get_user_entry(user, entry_id),
         {:ok, preview} <- Entries.get_publish_preview(entry) do
      render(conn, :preview,
        public_url_preview: preview.public_url_preview,
        assets: preview.assets,
        asset_count: preview.asset_count
      )
    end
  end

  # Private helpers

  defp get_user_entry(user, entry_id) do
    case Entries.get_user_entry(user, entry_id) do
      nil -> {:error, :not_found}
      entry -> {:ok, entry}
    end
  end

  defp ensure_username(%{username: nil}) do
    {:error, :unprocessable_entity, "You must set a username before publishing entries"}
  end
  defp ensure_username(%{username: username}) when is_binary(username) do
    {:ok, username}
  end

  defp ensure_has_content(entry) do
    case Entries.get_primary_representation(entry) do
      nil -> {:error, :unprocessable_entity, "Entry must have content before publishing"}
      %{content: nil} -> {:error, :unprocessable_entity, "Entry must have content before publishing"}
      %{content: ""} -> {:error, :unprocessable_entity, "Entry must have content before publishing"}
      _ -> {:ok, entry}
    end
  end

  defp list_entry_assets(entry) do
    entry = Onelist.Repo.preload(entry, :assets)

    Enum.map(entry.assets || [], fn asset ->
      %{
        id: asset.id,
        filename: asset.filename,
        size: asset.file_size,
        mime_type: asset.mime_type
      }
    end)
  end
end
