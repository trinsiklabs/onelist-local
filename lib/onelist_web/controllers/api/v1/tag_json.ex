defmodule OnelistWeb.Api.V1.TagJSON do
  @moduledoc """
  JSON rendering for Tag API responses.
  """

  alias Onelist.Tags.Tag

  @doc """
  Renders a list of tags with entry counts.
  """
  def index(%{tags: tags}) do
    %{data: Enum.map(tags, &tag_with_count_data/1)}
  end

  @doc """
  Renders a single tag.
  """
  def show(%{tag: tag}) do
    %{data: tag_data(tag)}
  end

  @doc """
  Renders a created tag.
  """
  def create(%{tag: tag}) do
    %{data: tag_data(tag)}
  end

  @doc """
  Renders an updated tag.
  """
  def update(%{tag: tag}) do
    %{data: tag_data(tag)}
  end

  defp tag_data(%Tag{} = tag) do
    %{
      id: tag.id,
      name: tag.name,
      inserted_at: tag.inserted_at,
      updated_at: tag.updated_at
    }
  end

  defp tag_with_count_data({%Tag{} = tag, count}) do
    tag_data(tag)
    |> Map.put(:entry_count, count)
  end

  defp tag_with_count_data(%Tag{} = tag) do
    tag_data(tag)
  end
end
