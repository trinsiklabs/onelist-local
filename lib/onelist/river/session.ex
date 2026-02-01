defmodule Onelist.River.Session do
  @moduledoc """
  A River conversation session.
  
  Sessions group messages together and track conversation state.
  A new session starts when the previous one times out (default 30 min).
  """
  
  use Ecto.Schema
  import Ecto.Changeset
  
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  
  schema "river_sessions" do
    field :started_at, :utc_datetime_usec
    field :last_message_at, :utc_datetime_usec
    field :message_count, :integer, default: 0
    field :metadata, :map, default: %{}
    
    belongs_to :user, Onelist.Accounts.User
    has_many :messages, Onelist.River.Message
    
    timestamps(type: :utc_datetime_usec)
  end
  
  def changeset(session, attrs) do
    session
    |> cast(attrs, [:user_id, :started_at, :last_message_at, :message_count, :metadata])
    |> validate_required([:user_id, :started_at, :last_message_at])
    |> foreign_key_constraint(:user_id)
  end
  
  def update_changeset(session, attrs) do
    session
    |> cast(attrs, [:last_message_at, :message_count, :metadata])
  end
end
