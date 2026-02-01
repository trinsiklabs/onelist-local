defmodule Onelist.River.Message do
  @moduledoc """
  A message in a River conversation.
  
  Messages have a role (user or river) and belong to a session.
  """
  
  use Ecto.Schema
  import Ecto.Changeset
  
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  
  @roles ~w(user river)
  
  schema "river_messages" do
    field :role, :string
    field :content, :string
    field :tokens_used, :integer
    field :metadata, :map, default: %{}
    
    belongs_to :session, Onelist.River.Session
    
    timestamps(type: :utc_datetime_usec)
  end
  
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:session_id, :role, :content, :tokens_used, :metadata])
    |> validate_required([:session_id, :role, :content])
    |> validate_inclusion(:role, @roles)
    |> foreign_key_constraint(:session_id)
  end
  
  def roles, do: @roles
end
