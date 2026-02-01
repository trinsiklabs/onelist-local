defmodule Onelist.Feeder.ExternalIntegration do
  @moduledoc """
  Schema for external integrations (OAuth connections, API sync sources).

  Stores credentials, sync configuration, and state for continuous sync sources
  like RSS feeds, Notion workspaces, Evernote accounts, etc.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_source_types ~w(rss evernote notion obsidian lifelog web_clipper)
  @valid_sync_statuses ~w(success partial failed syncing)

  schema "external_integrations" do
    belongs_to :user, Onelist.Accounts.User

    # Source identification
    field :source_type, :string
    field :source_name, :string

    # Authentication
    field :credentials, :map, default: %{}

    # Sync configuration
    field :sync_enabled, :boolean, default: true
    field :sync_frequency_minutes, :integer, default: 60
    field :sync_filter, :map

    # Sync state
    field :last_sync_at, :utc_datetime
    field :last_sync_status, :string
    field :last_sync_error, :string
    field :last_sync_stats, :map

    # Source-specific state
    field :sync_cursor, :map

    # Metadata
    field :metadata, :map

    timestamps()
  end

  @doc """
  Creates a changeset for a new integration.
  """
  def changeset(integration, attrs) do
    integration
    |> cast(attrs, [
      :user_id,
      :source_type,
      :source_name,
      :credentials,
      :sync_enabled,
      :sync_frequency_minutes,
      :sync_filter,
      :metadata
    ])
    |> validate_required([:user_id, :source_type, :credentials])
    |> validate_inclusion(:source_type, @valid_source_types)
    |> validate_number(:sync_frequency_minutes, greater_than: 0)
    |> unique_constraint([:user_id, :source_type, :source_name],
      name: :external_integrations_user_source_name_idx
    )
  end

  @doc """
  Updates an existing integration.
  """
  def update_changeset(integration, attrs) do
    integration
    |> cast(attrs, [
      :source_name,
      :credentials,
      :sync_enabled,
      :sync_frequency_minutes,
      :sync_filter,
      :metadata
    ])
    |> validate_number(:sync_frequency_minutes, greater_than: 0)
  end

  @doc """
  Updates sync state after a sync operation.
  """
  def sync_state_changeset(integration, attrs) do
    integration
    |> cast(attrs, [
      :last_sync_at,
      :last_sync_status,
      :last_sync_error,
      :last_sync_stats,
      :sync_cursor
    ])
    |> validate_inclusion(:last_sync_status, @valid_sync_statuses)
  end

  @doc """
  Returns list of valid source types.
  """
  def valid_source_types, do: @valid_source_types
end
