defmodule Onelist.Livelog.Message do
  @moduledoc """
  Ecto schema for redacted Livelog messages.

  These are the messages displayed on the public /livelog page.
  All content has been processed through the redaction engine.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "livelog_messages" do
    belongs_to :source_entry, Onelist.Entries.Entry

    field :source_message_id, :string
    field :role, :string
    field :content, :string
    field :original_timestamp, :utc_datetime_usec

    field :redaction_applied, :boolean, default: true
    field :patterns_matched, {:array, :string}, default: []
    field :blocked, :boolean, default: false
    field :block_reason, :string

    field :session_label, :string
    field :sequence_in_session, :integer

    has_one :audit_log, Onelist.Livelog.AuditLog, foreign_key: :livelog_message_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [
      :source_entry_id,
      :source_message_id,
      :role,
      :content,
      :original_timestamp,
      :redaction_applied,
      :patterns_matched,
      :blocked,
      :block_reason,
      :session_label,
      :sequence_in_session
    ])
    |> validate_required([:role, :content, :original_timestamp])
    |> validate_inclusion(:role, ["user", "assistant", "system"])
    |> unique_constraint(:source_message_id)
  end
end
