defmodule Onelist.Tags do
  @moduledoc """
  The Tags context.

  This module handles all operations related to tags and their
  associations with entries.
  """

  import Ecto.Query
  alias Onelist.Repo
  alias Onelist.Tags.Tag
  alias Onelist.Tags.EntryTag
  alias Onelist.Entries.Entry
  alias Onelist.Accounts.User

  # ---- Tag CRUD ----

  @doc """
  Creates a tag for a user.

  ## Examples

      iex> create_tag(user, %{name: "Important"})
      {:ok, %Tag{}}

      iex> create_tag(user, %{name: ""})
      {:error, %Ecto.Changeset{}}
  """
  def create_tag(%User{} = user, attrs) do
    %Tag{user_id: user.id}
    |> Tag.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a tag by id.

  ## Examples

      iex> get_tag("uuid")
      %Tag{}

      iex> get_tag("nonexistent")
      nil
  """
  def get_tag(id) when is_binary(id) do
    Repo.get(Tag, id)
  end

  @doc """
  Gets a tag that belongs to a specific user.

  ## Examples

      iex> get_user_tag(user, "uuid")
      %Tag{}

      iex> get_user_tag(user, "other_users_tag_id")
      nil
  """
  def get_user_tag(%User{} = user, id) when is_binary(id) do
    Repo.one(from t in Tag, where: t.id == ^id and t.user_id == ^user.id)
  end

  @doc """
  Gets or creates a tag by name for a user.

  This is case-insensitive - if a tag with the same name (different case)
  exists, the existing tag is returned.

  ## Examples

      iex> get_or_create_tag(user, "new-tag")
      {:ok, %Tag{}}

      iex> get_or_create_tag(user, "existing-tag")
      {:ok, %Tag{}}  # Returns existing tag
  """
  def get_or_create_tag(%User{} = user, name) when is_binary(name) do
    normalized_name = String.trim(name)

    case get_tag_by_name(user, normalized_name) do
      nil -> create_tag(user, %{name: normalized_name})
      tag -> {:ok, tag}
    end
  end

  @doc """
  Gets a tag by name for a user (case-insensitive).
  """
  def get_tag_by_name(%User{} = user, name) when is_binary(name) do
    Repo.one(
      from t in Tag,
        where: t.user_id == ^user.id and fragment("lower(?)", t.name) == ^String.downcase(name)
    )
  end

  @doc """
  Lists all tags for a user, ordered by name.

  ## Examples

      iex> list_user_tags(user)
      [%Tag{}, ...]
  """
  def list_user_tags(%User{} = user) do
    Repo.all(
      from t in Tag,
        where: t.user_id == ^user.id,
        order_by: [asc: t.name]
    )
  end

  @doc """
  Updates a tag.

  ## Examples

      iex> update_tag(tag, %{name: "New Name"})
      {:ok, %Tag{}}
  """
  def update_tag(%Tag{} = tag, attrs) do
    tag
    |> Tag.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a tag. This also removes all entry associations.

  ## Examples

      iex> delete_tag(tag)
      {:ok, %Tag{}}
  """
  def delete_tag(%Tag{} = tag) do
    Repo.delete(tag)
  end

  # ---- Entry-Tag associations ----

  @doc """
  Adds a tag to an entry.

  This is idempotent - adding the same tag twice has no effect.

  ## Examples

      iex> add_tag_to_entry(entry, tag)
      {:ok, %EntryTag{}}
  """
  def add_tag_to_entry(%Entry{} = entry, %Tag{} = tag) do
    attrs = %{entry_id: entry.id, tag_id: tag.id}

    %EntryTag{}
    |> EntryTag.changeset(attrs)
    |> Repo.insert(on_conflict: :nothing)
  end

  @doc """
  Removes a tag from an entry.

  ## Examples

      iex> remove_tag_from_entry(entry, tag)
      {:ok, entry_tag_or_nil}
  """
  def remove_tag_from_entry(%Entry{} = entry, %Tag{} = tag) do
    result =
      Repo.delete_all(
        from et in EntryTag,
          where: et.entry_id == ^entry.id and et.tag_id == ^tag.id
      )

    {:ok, result}
  end

  @doc """
  Lists all tags for an entry.

  ## Examples

      iex> list_entry_tags(entry)
      [%Tag{}, ...]
  """
  def list_entry_tags(%Entry{} = entry) do
    Repo.all(
      from t in Tag,
        join: et in EntryTag,
        on: et.tag_id == t.id,
        where: et.entry_id == ^entry.id,
        order_by: [asc: t.name]
    )
  end

  @doc """
  Lists all entries that have a specific tag.

  ## Examples

      iex> list_entries_by_tag(user, tag)
      [%Entry{}, ...]
  """
  def list_entries_by_tag(%User{} = user, %Tag{} = tag) do
    Repo.all(
      from e in Entry,
        join: et in EntryTag,
        on: et.entry_id == e.id,
        where: e.user_id == ^user.id and et.tag_id == ^tag.id,
        order_by: [desc: e.inserted_at]
    )
  end

  @doc """
  Counts the number of entries with a specific tag.

  ## Examples

      iex> count_entries_by_tag(tag)
      5
  """
  def count_entries_by_tag(%Tag{} = tag) do
    Repo.aggregate(
      from(et in EntryTag, where: et.tag_id == ^tag.id),
      :count,
      :tag_id
    )
  end

  @doc """
  Lists all tags with their entry counts for a user.

  ## Examples

      iex> list_user_tags_with_counts(user)
      [{%Tag{}, 5}, {%Tag{}, 3}, ...]
  """
  def list_user_tags_with_counts(%User{} = user) do
    Repo.all(
      from t in Tag,
        left_join: et in EntryTag,
        on: et.tag_id == t.id,
        where: t.user_id == ^user.id,
        group_by: t.id,
        select: {t, count(et.entry_id)},
        order_by: [asc: t.name]
    )
  end

  @doc """
  Sets the tags for an entry, replacing any existing tags.

  ## Examples

      iex> set_entry_tags(entry, [tag1, tag2])
      {:ok, [%EntryTag{}, ...]}
  """
  def set_entry_tags(%Entry{} = entry, tags) when is_list(tags) do
    # Remove all existing tags
    Repo.delete_all(from et in EntryTag, where: et.entry_id == ^entry.id)

    # Add new tags
    results =
      Enum.map(tags, fn tag ->
        add_tag_to_entry(entry, tag)
      end)

    {:ok, results}
  end
end
