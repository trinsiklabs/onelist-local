defmodule OnelistWeb.Api.V1.RepresentationVersionJSON do
  @moduledoc """
  JSON rendering for representation version API responses.
  """

  alias Onelist.Entries.RepresentationVersion

  @doc """
  Renders a list of versions.
  """
  def index(%{versions: versions}) do
    %{data: Enum.map(versions, &version_data/1)}
  end

  @doc """
  Renders content at a specific version.
  """
  def show_content(%{content: content, version: version}) do
    %{
      data: %{
        version: version,
        content: content
      }
    }
  end

  @doc """
  Renders a representation after revert.
  """
  def show_representation(%{representation: representation}) do
    %{
      data: %{
        id: representation.id,
        type: representation.type,
        content: representation.content,
        version: representation.version,
        updated_at: representation.updated_at
      }
    }
  end

  defp version_data(%RepresentationVersion{} = version) do
    %{
      id: version.id,
      version: version.version,
      version_type: version.version_type,
      byte_size: version.byte_size,
      inserted_at: version.inserted_at
    }
  end
end
