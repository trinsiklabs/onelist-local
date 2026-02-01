defmodule OnelistWeb.Api.V1.EntryJSON do
  @moduledoc """
  JSON rendering for Entry API responses.
  """

  alias Onelist.Entries.Entry
  alias Onelist.Entries.Representation

  @doc """
  Renders a list of entries with pagination metadata.
  """
  def index(%{entries: entries, meta: meta}) do
    %{
      data: Enum.map(entries, &entry_data/1),
      meta: meta
    }
  end

  @doc """
  Renders a single entry.
  """
  def show(%{entry: entry}) do
    %{data: entry_data(entry)}
  end

  @doc """
  Renders a created entry.
  """
  def create(%{entry: entry}) do
    %{data: entry_data(entry)}
  end

  @doc """
  Renders an updated entry.
  """
  def update(%{entry: entry}) do
    %{data: entry_data(entry)}
  end

  defp entry_data(%Entry{} = entry) do
    base = %{
      id: entry.id,
      public_id: entry.public_id,
      title: entry.title,
      entry_type: entry.entry_type,
      source_type: entry.source_type,
      public: entry.public,
      version: entry.version,
      content_created_at: entry.content_created_at,
      metadata: entry.metadata,
      inserted_at: entry.inserted_at,
      updated_at: entry.updated_at
    }

    # Include representations if loaded
    case entry.representations do
      %Ecto.Association.NotLoaded{} ->
        base

      representations when is_list(representations) ->
        Map.put(base, :representations, Enum.map(representations, &representation_data/1))
    end
  end

  defp representation_data(%Representation{} = rep) do
    %{
      id: rep.id,
      type: rep.type,
      content: rep.content,
      version: rep.version,
      mime_type: rep.mime_type,
      metadata: rep.metadata,
      inserted_at: rep.inserted_at,
      updated_at: rep.updated_at
    }
  end
end
