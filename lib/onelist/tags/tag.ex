defmodule Onelist.Tags.Tag do
  @moduledoc """
  Tag schema for organizing entries.

  Tags are user-scoped and can be applied to multiple entries.
  Each user can have their own set of tags with unique names.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "tags" do
    field :name, :string

    belongs_to :user, Onelist.Accounts.User
    many_to_many :entries, Onelist.Entries.Entry, join_through: "entry_tags"

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating or updating a tag.
  """
  def changeset(tag, attrs) do
    tag
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, max: 255)
    |> normalize_name()
    |> unsafe_validate_unique([:name, :user_id], Onelist.Repo, message: "has already been taken")
    |> unique_constraint(:name,
      name: :tags_user_id_name_unique,
      message: "has already been taken"
    )
  end

  defp normalize_name(changeset) do
    case get_change(changeset, :name) do
      nil -> changeset
      name -> put_change(changeset, :name, String.trim(name))
    end
  end
end
