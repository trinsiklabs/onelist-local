defmodule Onelist.Entries.AssetMirror do
  @moduledoc """
  Schema for tracking asset mirror sync status across backends.

  Each asset can be mirrored to multiple storage backends. This schema
  tracks the sync status, mode, and any errors for each mirror.

  ## Status Values

  - `pending` - Mirror queued but not yet started
  - `syncing` - Mirror sync in progress
  - `synced` - Mirror successfully synchronized
  - `failed` - Mirror sync failed (check error_message)

  ## Sync Modes

  - `full` - Full content synchronized
  - `stub` - Metadata only (for tiered sync)
  - `thumbnail` - Thumbnail/preview version (for images)
  - `waveform` - Waveform preview (for audio)
  - `poster` - Poster frame (for video)
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @status_values ~w(pending syncing synced failed)
  @sync_modes ~w(full stub thumbnail waveform poster metadata_only)

  schema "asset_mirrors" do
    field :backend, :string
    field :storage_path, :string
    field :status, :string, default: "pending"
    field :sync_mode, :string, default: "full"
    field :encrypted, :boolean, default: false
    field :synced_at, :utc_datetime_usec
    field :error_message, :string
    field :retry_count, :integer, default: 0

    belongs_to :asset, Onelist.Entries.Asset

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new asset mirror.
  """
  def changeset(mirror, attrs) do
    mirror
    |> cast(attrs, [
      :asset_id,
      :backend,
      :storage_path,
      :status,
      :sync_mode,
      :encrypted,
      :synced_at,
      :error_message,
      :retry_count
    ])
    |> validate_required([:asset_id, :backend, :storage_path])
    |> validate_inclusion(:status, @status_values)
    |> validate_inclusion(:sync_mode, @sync_modes)
    |> unique_constraint([:asset_id, :backend])
  end

  @doc """
  Changeset for updating mirror status.
  """
  def status_changeset(mirror, attrs) do
    mirror
    |> cast(attrs, [:status, :synced_at, :error_message, :retry_count])
    |> validate_inclusion(:status, @status_values)
  end

  @doc """
  Marks a mirror as syncing.
  """
  def mark_syncing(mirror) do
    status_changeset(mirror, %{status: "syncing", error_message: nil})
  end

  @doc """
  Marks a mirror as successfully synced.
  """
  def mark_synced(mirror) do
    status_changeset(mirror, %{
      status: "synced",
      synced_at: DateTime.utc_now(),
      error_message: nil
    })
  end

  @doc """
  Marks a mirror as failed with an error message.
  """
  def mark_failed(mirror, error_message) do
    status_changeset(mirror, %{
      status: "failed",
      error_message: truncate_error(error_message),
      retry_count: mirror.retry_count + 1
    })
  end

  @doc """
  Returns true if the mirror can be retried (under max attempts).
  """
  def can_retry?(%__MODULE__{retry_count: count}), do: count < 5

  @doc """
  Returns true if the mirror is in a terminal state.
  """
  def terminal?(%__MODULE__{status: status}), do: status in ["synced", "failed"]

  # Private

  defp truncate_error(message) when is_binary(message) do
    String.slice(message, 0, 1000)
  end

  defp truncate_error(other), do: inspect(other) |> truncate_error()
end
