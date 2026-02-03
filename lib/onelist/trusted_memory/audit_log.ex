defmodule Onelist.TrustedMemory.AuditLog do
  @moduledoc """
  Audit log for tracking all memory operations in trusted memory mode.

  Records all create, read, attempted_edit, and attempted_delete operations.
  This log is itself immutable and append-only.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @actions ~w(create read attempted_edit attempted_delete verify)

  schema "memory_audit_log" do
    field :action, :string
    field :actor, :string
    # success, denied
    field :outcome, :string
    field :details, :map, default: %{}

    belongs_to :user, Onelist.Accounts.User
    belongs_to :entry, Onelist.Entries.Entry

    timestamps()
  end

  @doc """
  Changeset for creating an audit log entry.
  """
  def changeset(audit_log, attrs) do
    audit_log
    |> cast(attrs, [:user_id, :entry_id, :action, :actor, :outcome, :details])
    |> validate_required([:user_id, :action, :outcome])
    |> validate_inclusion(:action, @actions)
  end
end
