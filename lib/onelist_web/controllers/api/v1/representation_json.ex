defmodule OnelistWeb.Api.V1.RepresentationJSON do
  @moduledoc """
  JSON rendering for representation API responses.
  """

  alias Onelist.Entries.Representation

  @doc """
  Renders a list of representations.
  """
  def index(%{representations: representations}) do
    %{data: Enum.map(representations, &representation_data/1)}
  end

  @doc """
  Renders a single representation.
  """
  def show(%{representation: representation}) do
    %{data: representation_data(representation)}
  end

  defp representation_data(%Representation{} = rep) do
    %{
      id: rep.id,
      type: rep.type,
      content: rep.content,
      storage_path: rep.storage_path,
      mime_type: rep.mime_type,
      version: rep.version,
      metadata: rep.metadata,
      inserted_at: rep.inserted_at,
      updated_at: rep.updated_at
    }
  end
end
