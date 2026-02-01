defmodule Onelist.TrustedMemory.Checkpoint do
  @moduledoc """
  Schema for memory checkpoints used in trusted memory rollback system.
  
  Checkpoints allow "rolling back" an AI's memory to a previous point
  without actually deleting any entries. Entries after the checkpoint's
  `after_sequence` are simply filtered out of queries.
  
  Key constraints:
  - Only humans can create rollback checkpoints (AI cannot roll back its own memory)
  - Checkpoints are never deleted, only deactivated
  - Full history is always preserved
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @checkpoint_types ~w(rollback snapshot recovery)
  @creators ~w(human system)

  schema "memory_checkpoints" do
    field :checkpoint_type, :string
    field :reason, :string
    field :after_sequence, :integer
    field :created_by, :string
    field :authorized_by, :string
    field :active, :boolean, default: true
    field :deactivated_at, :utc_datetime_usec

    belongs_to :user, Onelist.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:user_id, :checkpoint_type, :after_sequence, :created_by]
  @optional_fields [:reason, :authorized_by, :active, :deactivated_at]

  @doc """
  Changeset for creating a checkpoint.
  """
  def changeset(checkpoint, attrs) do
    checkpoint
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:checkpoint_type, @checkpoint_types)
    |> validate_inclusion(:created_by, @creators)
    |> validate_rollback_authorization()
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Changeset for deactivating a checkpoint (recovery).
  """
  def deactivate_changeset(checkpoint) do
    checkpoint
    |> change(%{
      active: false,
      deactivated_at: DateTime.utc_now()
    })
  end

  # Rollback checkpoints require human authorization
  defp validate_rollback_authorization(changeset) do
    checkpoint_type = get_field(changeset, :checkpoint_type)
    authorized_by = get_field(changeset, :authorized_by)

    if checkpoint_type == "rollback" && authorized_by != "human" do
      add_error(changeset, :authorized_by, "rollback checkpoints require human authorization")
    else
      changeset
    end
  end

  @doc """
  Returns the list of valid checkpoint types.
  """
  def checkpoint_types, do: @checkpoint_types
end
