defmodule Onelist.Feeder.SourceEntryMapping do
  @moduledoc """
  Schema for mapping source IDs to Onelist entry IDs.

  Tracks which external source items have been imported and their corresponding
  Onelist entries. Used for:
  - Deduplication (don't re-import existing items)
  - Updates (sync changes from source to entry)
  - Backlinks (show source origin in entry metadata)
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "source_entry_mappings" do
    belongs_to :user, Onelist.Accounts.User
    belongs_to :integration, Onelist.Feeder.ExternalIntegration
    belongs_to :entry, Onelist.Entries.Entry

    # Source identification
    field :source_type, :string
    field :source_id, :string
    field :source_parent_id, :string

    # Sync metadata
    field :source_updated_at, :utc_datetime
    field :last_synced_at, :utc_datetime
    field :sync_hash, :string

    timestamps()
  end

  @doc """
  Creates a changeset for a new mapping.
  """
  def changeset(mapping, attrs) do
    mapping
    |> cast(attrs, [
      :user_id,
      :integration_id,
      :entry_id,
      :source_type,
      :source_id,
      :source_parent_id,
      :source_updated_at,
      :last_synced_at,
      :sync_hash
    ])
    |> validate_required([:user_id, :entry_id, :source_type, :source_id])
    |> put_change(:last_synced_at, DateTime.utc_now())
    |> unique_constraint([:user_id, :source_type, :source_id],
      name: :source_entry_mappings_user_source_idx
    )
  end

  @doc """
  Updates sync metadata.
  """
  def update_changeset(mapping, attrs) do
    mapping
    |> cast(attrs, [:source_updated_at, :last_synced_at, :sync_hash])
    |> put_change(:last_synced_at, DateTime.utc_now())
  end
end
