defmodule Onelist.Entries.RepresentationVersion do
  @moduledoc """
  Schema for tracking version history of representations.

  Supports a hybrid versioning approach:
  - Full snapshots stored periodically (daily or after N diffs)
  - Incremental diffs stored between snapshots

  This allows efficient storage while maintaining the ability to
  reconstruct content at any historical version.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @max_diff_size 1_048_576  # 1MB

  schema "representation_versions" do
    belongs_to :representation, Onelist.Entries.Representation
    belongs_to :user, Onelist.Accounts.User

    field :content, :string      # Full snapshot content
    field :diff, :string         # Diff from previous version
    field :version, :integer     # Version number before this change
    field :version_type, :string # "snapshot" or "diff"
    field :byte_size, :integer   # Size of content or diff

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc """
  Returns the maximum allowed diff size in bytes.
  If a diff exceeds this size, a full snapshot should be created instead.
  """
  def max_diff_size, do: @max_diff_size

  @doc """
  Creates a changeset for a new version record.
  """
  def changeset(version, attrs) do
    version
    |> cast(attrs, [:representation_id, :user_id, :content, :diff, :version, :version_type, :byte_size])
    |> validate_required([:representation_id, :user_id, :version, :version_type])
    |> validate_inclusion(:version_type, ["snapshot", "diff"])
    |> validate_content_or_diff()
    |> foreign_key_constraint(:representation_id)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Creates a changeset for a snapshot version.
  """
  def snapshot_changeset(version, attrs) do
    version
    |> cast(attrs, [:representation_id, :user_id, :content, :version, :byte_size])
    |> validate_required([:representation_id, :user_id, :content, :version])
    |> put_change(:version_type, "snapshot")
    |> put_change(:diff, nil)
    |> foreign_key_constraint(:representation_id)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Creates a changeset for a diff version.
  """
  def diff_changeset(version, attrs) do
    version
    |> cast(attrs, [:representation_id, :user_id, :diff, :version, :byte_size])
    |> validate_required([:representation_id, :user_id, :diff, :version])
    |> put_change(:version_type, "diff")
    |> put_change(:content, nil)
    |> validate_diff_size()
    |> foreign_key_constraint(:representation_id)
    |> foreign_key_constraint(:user_id)
  end

  defp validate_content_or_diff(changeset) do
    content = get_field(changeset, :content)
    diff = get_field(changeset, :diff)
    version_type = get_field(changeset, :version_type)

    cond do
      version_type == "snapshot" and is_nil(content) ->
        add_error(changeset, :content, "is required for snapshot versions")

      version_type == "diff" and is_nil(diff) ->
        add_error(changeset, :diff, "is required for diff versions")

      not is_nil(content) and not is_nil(diff) ->
        add_error(changeset, :diff, "cannot have both content and diff")

      true ->
        changeset
    end
  end

  defp validate_diff_size(changeset) do
    diff = get_field(changeset, :diff)

    if diff && byte_size(diff) > @max_diff_size do
      add_error(changeset, :diff, "exceeds maximum size of #{@max_diff_size} bytes")
    else
      changeset
    end
  end
end
