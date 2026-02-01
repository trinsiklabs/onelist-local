defmodule OnelistWeb.Api.V1.EntryPublishJSON do
  @moduledoc """
  JSON rendering for entry publish API responses.
  """

  @doc """
  Renders publish response with public URL and published assets.
  """
  def publish(%{public_url: public_url, assets_published: assets}) do
    %{
      public_url: public_url,
      assets_published: assets
    }
  end

  @doc """
  Renders unpublish response with removed assets.
  """
  def unpublish(%{assets_removed: assets}) do
    %{
      message: "Entry unpublished successfully",
      assets_removed: assets
    }
  end

  @doc """
  Renders publish preview with URL and asset details.
  """
  def preview(%{public_url_preview: url, assets: assets, asset_count: count}) do
    %{
      public_url_preview: url,
      assets: assets,
      asset_count: count
    }
  end
end
