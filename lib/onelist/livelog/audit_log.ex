defmodule Onelist.Livelog.AuditLog do
  @moduledoc """
  Audit trail for redaction decisions.

  Every message processed through the Livelog system gets an audit entry,
  even if blocked. This enables compliance verification and pattern tuning.

  IMPORTANT: For blocked messages, we store only hashes - NEVER the original content.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "livelog_audit_log" do
    belongs_to :livelog_message, Onelist.Livelog.Message

    field :original_content_hash, :string
    field :redacted_content_hash, :string
    # "redacted", "blocked", "allowed"
    field :action, :string
    # Which layer made the decision (1-5)
    field :layer, :integer
    field :patterns_fired, {:array, :string}, default: []
    field :processing_time_us, :integer

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(audit_log, attrs) do
    audit_log
    |> cast(attrs, [
      :livelog_message_id,
      :original_content_hash,
      :redacted_content_hash,
      :action,
      :layer,
      :patterns_fired,
      :processing_time_us
    ])
    |> validate_required([:original_content_hash, :redacted_content_hash, :action])
    |> validate_inclusion(:action, ["redacted", "blocked", "allowed"])
  end
end
