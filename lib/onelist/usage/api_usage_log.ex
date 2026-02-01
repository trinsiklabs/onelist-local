defmodule Onelist.Usage.ApiUsageLog do
  @moduledoc """
  Schema for tracking API usage (tokens, costs) across providers.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "api_usage_log" do
    field :provider, :string
    field :model, :string
    field :operation, :string
    field :input_tokens, :integer, default: 0
    field :output_tokens, :integer, default: 0
    field :total_tokens, :integer, default: 0
    field :cost_cents, :decimal
    field :metadata, :map, default: %{}

    belongs_to :user, Onelist.Accounts.User
    belongs_to :entry, Onelist.Entries.Entry

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(log, attrs) do
    log
    |> cast(attrs, [:provider, :model, :operation, :input_tokens, :output_tokens, :total_tokens, :cost_cents, :user_id, :entry_id, :metadata])
    |> validate_required([:provider, :operation])
    |> calculate_total_tokens()
  end

  defp calculate_total_tokens(changeset) do
    input = get_field(changeset, :input_tokens) || 0
    output = get_field(changeset, :output_tokens) || 0
    put_change(changeset, :total_tokens, input + output)
  end
end
