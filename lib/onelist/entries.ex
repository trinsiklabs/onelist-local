defmodule Onelist.Entries do
  @moduledoc """
  The Entries context.

  This module handles all operations related to entries, representations,
  and assets - the core content storage for Onelist.
  """

  import Ecto.Query
  alias Onelist.Repo
  alias Onelist.Entries.Entry
  alias Onelist.Entries.EntryLink
  alias Onelist.Entries.Representation
  alias Onelist.Entries.Asset
  alias Onelist.Accounts.User
  alias Onelist.Reader
  alias Onelist.Searcher
  alias Onelist.TrustedMemory

  require Logger

  # ---- Entry CRUD ----

  @doc """
  Creates an entry for a user.

  After successful creation, automatically enqueues processing based on user settings:
  - Reader processing (memories, tags, summaries) if `reader_enabled?/1` is true
  - Searcher embedding if `auto_embed_on_create?/1` is true

  ## Options

    * `:skip_auto_processing` - Skip automatic processing (default: false)

  ## Examples

      iex> create_entry(user, %{title: "My Note", entry_type: "note"})
      {:ok, %Entry{}}

      iex> create_entry(user, %{entry_type: "invalid"})
      {:error, %Ecto.Changeset{}}

      iex> create_entry(user, %{title: "Note"}, skip_auto_processing: true)
      {:ok, %Entry{}}
  """
  def create_entry(%User{} = user, attrs, opts \\ []) do
    # Add trusted memory hash chain if enabled for this user
    attrs = maybe_add_trusted_memory_fields(user, attrs)
    
    result =
      %Entry{user_id: user.id}
      |> Entry.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, entry} ->
        # Log the creation for trusted memory accounts
        if TrustedMemory.enabled?(user) do
          TrustedMemory.log_operation(user.id, entry.id, "create", "success")
        end
        
        unless Keyword.get(opts, :skip_auto_processing, false) do
          trigger_auto_processing_on_create(entry)
        end

        {:ok, entry}

      error ->
        error
    end
  end

  # Add hash chain fields for trusted memory accounts
  defp maybe_add_trusted_memory_fields(user, attrs) do
    if TrustedMemory.enabled?(user) do
      case TrustedMemory.create_entry(user, attrs) do
        {:ok, trusted_attrs} when is_map(trusted_attrs) ->
          # Convert trusted_attrs to match the key type of attrs (string vs atom)
          # API requests use string keys, so we need to normalize
          normalized_attrs = normalize_keys_to_match(trusted_attrs, attrs)
          Map.merge(attrs, normalized_attrs)
        _ ->
          attrs
      end
    else
      attrs
    end
  end

  # Normalize keys to match the target map's key type
  defp normalize_keys_to_match(source, target) do
    # Check if target uses string keys by looking at first key
    uses_string_keys = case Map.keys(target) |> List.first() do
      key when is_binary(key) -> true
      _ -> false
    end

    if uses_string_keys do
      for {k, v} <- source, into: %{} do
        key = if is_atom(k), do: Atom.to_string(k), else: k
        {key, v}
      end
    else
      source
    end
  end

  @doc """
  Gets an entry by id.

  ## Examples

      iex> get_entry("uuid")
      %Entry{}

      iex> get_entry("nonexistent")
      nil
  """
  def get_entry(id) when is_binary(id) do
    Repo.get(Entry, id)
  end

  @doc """
  Gets an entry by public_id.

  ## Examples

      iex> get_entry_by_public_id("abc123")
      %Entry{}

      iex> get_entry_by_public_id("nonexistent")
      nil
  """
  def get_entry_by_public_id(public_id) when is_binary(public_id) do
    Repo.get_by(Entry, public_id: public_id)
  end

  @doc """
  Gets an entry that belongs to a specific user.

  Returns nil if the entry doesn't exist or doesn't belong to the user.

  ## Examples

      iex> get_user_entry(user, "uuid")
      %Entry{}

      iex> get_user_entry(user, "other_users_entry_id")
      nil
  """
  def get_user_entry(%User{} = user, id) when is_binary(id) do
    Repo.one(from e in Entry, where: e.id == ^id and e.user_id == ^user.id)
  end

  @doc """
  Updates an entry.

  After successful update, automatically enqueues processing based on user settings:
  - Reader processing (memories, tags, summaries) if `reader_enabled_on_update?/1` is true
  - Searcher embedding if `auto_embed_on_update?/1` is true

  ## Options

    * `:skip_auto_processing` - Skip automatic processing (default: false)

  ## Examples

      iex> update_entry(entry, %{title: "New Title"})
      {:ok, %Entry{}}

      iex> update_entry(entry, %{entry_type: "invalid"})
      {:error, %Ecto.Changeset{}}

      iex> update_entry(entry, %{title: "New"}, skip_auto_processing: true)
      {:ok, %Entry{}}
  """
  def update_entry(%Entry{} = entry, attrs, opts \\ []) do
    # Check trusted memory guard
    user = Repo.get(User, entry.user_id)
    
    case TrustedMemory.guard_update(user, entry.id) do
      {:error, :trusted_memory_immutable} ->
        {:error, :trusted_memory_immutable}
      
      :ok ->
        result =
          entry
          |> Entry.update_changeset(attrs)
          |> Repo.update()

        case result do
          {:ok, updated_entry} ->
            unless Keyword.get(opts, :skip_auto_processing, false) do
              trigger_auto_processing_on_update(updated_entry)
            end

            {:ok, updated_entry}

          error ->
            error
        end
    end
  end

  @doc """
  Deletes an entry and all associated representations and assets.

  Returns `{:error, :trusted_memory_immutable}` for AI accounts with trusted memory.

  ## Examples

      iex> delete_entry(entry)
      {:ok, %Entry{}}
  """
  def delete_entry(%Entry{} = entry) do
    # Check trusted memory guard
    user = Repo.get(User, entry.user_id)
    
    case TrustedMemory.guard_delete(user, entry.id) do
      {:error, :trusted_memory_immutable} ->
        {:error, :trusted_memory_immutable}
      
      :ok ->
        Repo.delete(entry)
    end
  end

  @doc """
  Lists all entries for a user with optional filtering and pagination.

  ## Options

    * `:entry_type` - Filter by entry type (e.g., "note", "photo")
    * `:source_type` - Filter by source type (e.g., "manual", "web_clip")
    * `:public` - Filter by public status (true/false)
    * `:limit` - Maximum number of entries to return
    * `:offset` - Number of entries to skip
    * `:order_by` - Field to order by (default: :inserted_at)
    * `:order` - Sort order (:asc or :desc, default: :desc)

  ## Examples

      iex> list_user_entries(user)
      [%Entry{}, ...]

      iex> list_user_entries(user, entry_type: "note", limit: 10)
      [%Entry{}, ...]
  """
  def list_user_entries(%User{} = user, opts \\ []) do
    Entry
    |> where([e], e.user_id == ^user.id)
    |> apply_filters(opts)
    |> apply_ordering(opts)
    |> apply_pagination(opts)
    |> Repo.all()
  end

  defp apply_filters(query, opts) do
    query
    |> filter_by_entry_type(opts[:entry_type])
    |> filter_by_source_type(opts[:source_type])
    |> filter_by_public(opts[:public])
  end

  defp filter_by_entry_type(query, nil), do: query
  defp filter_by_entry_type(query, entry_type) do
    where(query, [e], e.entry_type == ^entry_type)
  end

  defp filter_by_source_type(query, nil), do: query
  defp filter_by_source_type(query, source_type) do
    where(query, [e], e.source_type == ^source_type)
  end

  defp filter_by_public(query, nil), do: query
  defp filter_by_public(query, public) do
    where(query, [e], e.public == ^public)
  end

  defp apply_ordering(query, opts) do
    order_field = opts[:order_by] || :inserted_at
    order_direction = opts[:order] || :desc

    order_by(query, [e], [{^order_direction, field(e, ^order_field)}])
  end

  defp apply_pagination(query, opts) do
    query
    |> maybe_limit(opts[:limit])
    |> maybe_offset(opts[:offset])
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit), do: limit(query, ^limit)

  defp maybe_offset(query, nil), do: query
  defp maybe_offset(query, offset), do: offset(query, ^offset)

  @doc """
  Searches entries for a user by title.

  ## Examples

      iex> search_entries(user, "meeting notes")
      [%Entry{}, ...]
  """
  def search_entries(%User{} = user, query, opts \\ []) do
    search_term = "%#{query}%"

    Entry
    |> where([e], e.user_id == ^user.id)
    |> where([e], ilike(e.title, ^search_term))
    |> apply_filters(opts)
    |> apply_ordering(opts)
    |> apply_pagination(opts)
    |> Repo.all()
  end

  # ---- Representation CRUD ----

  @doc """
  Adds a representation to an entry.

  ## Examples

      iex> add_representation(entry, %{type: "markdown", content: "# Hello"})
      {:ok, %Representation{}}
  """
  def add_representation(%Entry{} = entry, attrs) do
    %Representation{entry_id: entry.id}
    |> Representation.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a representation.

  ## Examples

      iex> update_representation(representation, %{content: "Updated content"})
      {:ok, %Representation{}}
  """
  def update_representation(%Representation{} = representation, attrs) do
    representation
    |> Representation.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Gets a representation by id.
  """
  def get_representation(id) when is_binary(id) do
    Repo.get(Representation, id)
  end

  @doc """
  Lists all representations for an entry.
  """
  def list_representations(%Entry{} = entry) do
    Repo.all(from r in Representation, where: r.entry_id == ^entry.id, order_by: r.inserted_at)
  end

  @doc """
  Gets the primary representation for an entry.

  Returns the markdown representation if available, otherwise the first representation.
  """
  def get_primary_representation(%Entry{} = entry) do
    # First try to get markdown representation
    markdown = Repo.one(
      from r in Representation,
      where: r.entry_id == ^entry.id and r.type == "markdown",
      limit: 1
    )

    if markdown do
      markdown
    else
      # Otherwise get the first representation
      Repo.one(
        from r in Representation,
        where: r.entry_id == ^entry.id,
        order_by: r.inserted_at,
        limit: 1
      )
    end
  end

  @doc """
  Deletes a representation.
  """
  def delete_representation(%Representation{} = representation) do
    Repo.delete(representation)
  end

  # ---- Asset CRUD ----

  @doc """
  Adds an asset to an entry.

  ## Examples

      iex> add_asset(entry, %{filename: "image.jpg", mime_type: "image/jpeg", storage_path: "/uploads/..."})
      {:ok, %Asset{}}
  """
  def add_asset(%Entry{} = entry, attrs) do
    %Asset{entry_id: entry.id}
    |> Asset.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets an asset by id.
  """
  def get_asset(id) when is_binary(id) do
    Repo.get(Asset, id)
  end

  @doc """
  Lists all assets for an entry.
  """
  def list_assets(%Entry{} = entry) do
    Repo.all(from a in Asset, where: a.entry_id == ^entry.id, order_by: a.inserted_at)
  end

  @doc """
  Lists assets for a specific representation.
  """
  def list_representation_assets(%Representation{} = representation) do
    Repo.all(from a in Asset, where: a.representation_id == ^representation.id, order_by: a.inserted_at)
  end

  @doc """
  Updates an asset.
  """
  def update_asset(%Asset{} = asset, attrs) do
    asset
    |> Asset.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an asset.
  """
  def delete_asset(%Asset{} = asset) do
    Repo.delete(asset)
  end

  # ---- Entry with preloads ----

  @doc """
  Gets an entry with its representations preloaded.
  """
  def get_entry_with_representations(id) when is_binary(id) do
    Repo.one(
      from e in Entry,
      where: e.id == ^id,
      preload: [:representations]
    )
  end

  @doc """
  Gets an entry with all associations preloaded.
  """
  def get_entry_with_all(id) when is_binary(id) do
    Repo.one(
      from e in Entry,
      where: e.id == ^id,
      preload: [:representations, :assets]
    )
  end

  @doc """
  Counts entries for a user, optionally filtered by type.
  """
  def count_user_entries(%User{} = user, opts \\ []) do
    Entry
    |> where([e], e.user_id == ^user.id)
    |> apply_filters(opts)
    |> Repo.aggregate(:count, :id)
  end

  # ---- Version History ----

  alias Onelist.Entries.RepresentationVersion

  @doc """
  Creates a version record for a representation.

  Compares old and new content, generating a diff. If the diff exceeds
  the maximum size, creates a full snapshot instead.

  ## Examples

      iex> create_version(representation, user, "old content", "new content")
      {:ok, %RepresentationVersion{}}
  """
  def create_version(%Representation{} = representation, %User{} = user, old_content, new_content) do
    old_content = old_content || ""
    new_content = new_content || ""

    diff = :diffy.diff(old_content, new_content)
    diff_text = format_diff(diff)
    diff_size = byte_size(diff_text)

    if diff_size > RepresentationVersion.max_diff_size() do
      create_snapshot(representation, user, old_content)
    else
      create_diff_version(representation, user, diff_text, diff_size)
    end
  end

  defp format_diff(diff) do
    diff
    |> Enum.map(fn
      {:equal, text} -> "= #{text}"
      {:insert, text} -> "+ #{text}"
      {:delete, text} -> "- #{text}"
    end)
    |> Enum.join("\n")
  end

  @doc """
  Creates a full snapshot version of a representation's content.

  ## Examples

      iex> create_snapshot(representation, user)
      {:ok, %RepresentationVersion{}}
  """
  def create_snapshot(%Representation{} = representation, %User{} = user, content \\ nil) do
    content = content || representation.content || ""

    attrs = %{
      representation_id: representation.id,
      user_id: user.id,
      content: content,
      version: representation.version,
      byte_size: byte_size(content)
    }

    %RepresentationVersion{}
    |> RepresentationVersion.snapshot_changeset(attrs)
    |> Repo.insert()
  end

  defp create_diff_version(%Representation{} = representation, %User{} = user, diff_text, diff_size) do
    attrs = %{
      representation_id: representation.id,
      user_id: user.id,
      diff: diff_text,
      version: representation.version,
      byte_size: diff_size
    }

    %RepresentationVersion{}
    |> RepresentationVersion.diff_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists version history for a representation.

  Returns versions in reverse chronological order (newest first).

  ## Options

    * `:limit` - Maximum number of versions to return (default: 50)

  ## Examples

      iex> list_representation_versions(representation)
      [%RepresentationVersion{}, ...]
  """
  def list_representation_versions(%Representation{} = representation, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(v in RepresentationVersion,
      where: v.representation_id == ^representation.id,
      order_by: [desc: v.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Gets a specific version by ID.
  """
  def get_representation_version(id) when is_binary(id) do
    Repo.get(RepresentationVersion, id)
  end

  @doc """
  Reconstructs content at a specific version by applying diffs.

  Finds the nearest snapshot at or before the target version, then
  applies diffs to reconstruct the content at that point.

  ## Examples

      iex> get_content_at_version(representation, 5)
      {:ok, "content at version 5"}

      iex> get_content_at_version(representation, 999)
      {:error, :version_not_found}
  """
  def get_content_at_version(%Representation{} = representation, target_version) do
    # Get all versions from the beginning up to and including the target
    versions =
      from(v in RepresentationVersion,
        where: v.representation_id == ^representation.id,
        where: v.version <= ^target_version,
        order_by: [asc: v.version]
      )
      |> Repo.all()

    if Enum.empty?(versions) do
      {:error, :version_not_found}
    else
      reconstruct_content(versions)
    end
  end

  defp reconstruct_content(versions) do
    # Find the latest snapshot
    {snapshots, diffs_after} = find_latest_snapshot(versions)

    case snapshots do
      nil ->
        {:error, :no_snapshot_found}

      snapshot ->
        # Start with snapshot content and apply subsequent diffs
        content = apply_diffs(snapshot.content || "", diffs_after)
        {:ok, content}
    end
  end

  defp find_latest_snapshot(versions) do
    # Find the latest snapshot in the list
    snapshots =
      versions
      |> Enum.filter(&(&1.version_type == "snapshot"))

    case List.last(snapshots) do
      nil ->
        {nil, versions}

      snapshot ->
        # Get all versions after the snapshot
        diffs_after =
          versions
          |> Enum.drop_while(&(&1.id != snapshot.id))
          |> Enum.drop(1)  # Drop the snapshot itself
          |> Enum.filter(&(&1.version_type == "diff"))

        {snapshot, diffs_after}
    end
  end

  defp apply_diffs(content, diffs) do
    Enum.reduce(diffs, content, fn version, acc ->
      apply_single_diff(acc, version.diff)
    end)
  end

  defp apply_single_diff(content, diff_text) when is_binary(diff_text) do
    # Parse the diff format and apply changes
    diff_text
    |> String.split("\n")
    |> Enum.reduce({content, 0}, fn line, {acc, _pos} ->
      cond do
        String.starts_with?(line, "= ") ->
          # Equal - content stays the same
          {acc, 0}

        String.starts_with?(line, "+ ") ->
          # Insert - add the text
          insert_text = String.slice(line, 2..-1//1)
          {acc <> insert_text, 0}

        String.starts_with?(line, "- ") ->
          # Delete - remove from content
          delete_text = String.slice(line, 2..-1//1)
          {String.replace(acc, delete_text, "", global: false), 0}

        true ->
          {acc, 0}
      end
    end)
    |> elem(0)
  end

  defp apply_single_diff(content, _), do: content

  # ---- Entry Links ----

  @doc """
  Creates a link between two entries.

  ## Examples

      iex> create_link(topic, reply, "has_reply")
      {:ok, %EntryLink{}}

      iex> create_link(topic, reply, "has_reply", %{reply_order: 1})
      {:ok, %EntryLink{}}

      iex> create_link(topic, reply, "invalid_type")
      {:error, %Ecto.Changeset{}}
  """
  def create_link(%Entry{} = source, %Entry{} = target, link_type, metadata \\ %{}) do
    %EntryLink{}
    |> EntryLink.changeset(%{
      source_entry_id: source.id,
      target_entry_id: target.id,
      link_type: link_type,
      metadata: metadata
    })
    |> Repo.insert()
  end

  @doc """
  Deletes an entry link.

  ## Examples

      iex> delete_link(link)
      {:ok, %EntryLink{}}
  """
  def delete_link(%EntryLink{} = link) do
    Repo.delete(link)
  end

  @doc """
  Gets an entry link by ID.

  ## Examples

      iex> get_link("uuid")
      %EntryLink{}

      iex> get_link("nonexistent")
      nil
  """
  def get_link(id) when is_binary(id) do
    Repo.get(EntryLink, id)
  end

  @doc """
  Lists outgoing links from an entry (links where the entry is the source).

  ## Options

    * `:link_type` - Filter by link type (e.g., "has_reply")

  ## Examples

      iex> list_outgoing_links(entry)
      [%EntryLink{}, ...]

      iex> list_outgoing_links(entry, link_type: "has_reply")
      [%EntryLink{}, ...]
  """
  def list_outgoing_links(%Entry{} = entry, opts \\ []) do
    EntryLink
    |> where([l], l.source_entry_id == ^entry.id)
    |> filter_by_link_type(opts[:link_type])
    |> order_by([l], asc: l.inserted_at)
    |> Repo.all()
  end

  @doc """
  Lists incoming links to an entry (links where the entry is the target).

  ## Options

    * `:link_type` - Filter by link type (e.g., "reply_to")

  ## Examples

      iex> list_incoming_links(entry)
      [%EntryLink{}, ...]

      iex> list_incoming_links(entry, link_type: "reply_to")
      [%EntryLink{}, ...]
  """
  def list_incoming_links(%Entry{} = entry, opts \\ []) do
    EntryLink
    |> where([l], l.target_entry_id == ^entry.id)
    |> filter_by_link_type(opts[:link_type])
    |> order_by([l], asc: l.inserted_at)
    |> Repo.all()
  end

  defp filter_by_link_type(query, nil), do: query
  defp filter_by_link_type(query, link_type) do
    where(query, [l], l.link_type == ^link_type)
  end

  @doc """
  Lists linked entries with preloaded data.

  ## Direction

    * `:outgoing` - Returns entries that this entry links TO (target entries)
    * `:incoming` - Returns entries that link TO this entry (source entries)

  ## Options

    * `:link_type` - Filter by link type

  ## Examples

      iex> list_linked_entries(topic, :outgoing, link_type: "has_reply")
      [%Entry{}, ...]  # Returns replies to the topic

      iex> list_linked_entries(reply, :incoming, link_type: "has_reply")
      [%Entry{}, ...]  # Returns topics that this is a reply to
  """
  def list_linked_entries(entry, direction, opts \\ [])

  def list_linked_entries(%Entry{} = entry, :outgoing, opts) do
    from(e in Entry,
      join: l in EntryLink,
      on: l.target_entry_id == e.id,
      where: l.source_entry_id == ^entry.id,
      order_by: [asc: l.inserted_at]
    )
    |> filter_linked_by_type(opts[:link_type])
    |> Repo.all()
  end

  def list_linked_entries(%Entry{} = entry, :incoming, opts) do
    from(e in Entry,
      join: l in EntryLink,
      on: l.source_entry_id == e.id,
      where: l.target_entry_id == ^entry.id,
      order_by: [asc: l.inserted_at]
    )
    |> filter_linked_by_type(opts[:link_type])
    |> Repo.all()
  end

  defp filter_linked_by_type(query, nil), do: query
  defp filter_linked_by_type(query, link_type) do
    where(query, [_e, l], l.link_type == ^link_type)
  end

  @doc """
  Checks if a link exists between two entries with a specific type.

  ## Examples

      iex> link_exists?(topic, reply, "has_reply")
      true

      iex> link_exists?(topic, reply, "related_to")
      false
  """
  def link_exists?(%Entry{} = source, %Entry{} = target, link_type) do
    from(l in EntryLink,
      where: l.source_entry_id == ^source.id,
      where: l.target_entry_id == ^target.id,
      where: l.link_type == ^link_type,
      select: count(l.id)
    )
    |> Repo.one()
    |> Kernel.>(0)
  end

  @doc """
  Reverts a representation to a specific version.

  Creates a new version record with the reverted content.

  ## Examples

      iex> revert_to_version(representation, 5, user)
      {:ok, %Representation{}}
  """
  def revert_to_version(%Representation{} = representation, version, %User{} = user) do
    with {:ok, content} <- get_content_at_version(representation, version) do
      old_content = representation.content

      # Update the representation with the old content
      case update_representation(representation, %{content: content}) do
        {:ok, updated_rep} ->
          # Create a version record for this revert
          create_version(updated_rep, user, old_content, content)
          {:ok, updated_rep}

        error ->
          error
      end
    end
  end

  @doc """
  Checks if a snapshot is needed for a representation.

  Returns true if:
  - No snapshot exists
  - More than `max_diffs` diffs since the last snapshot
  - More than `max_hours` hours since the last snapshot

  ## Options

    * `:max_diffs_between_snapshots` - Maximum diffs before requiring a snapshot (default: 50)
    * `:max_hours_between_snapshots` - Maximum hours before requiring a snapshot (default: 24)

  ## Examples

      iex> needs_snapshot?(representation)
      true
  """
  def needs_snapshot?(%Representation{} = representation, opts \\ []) do
    max_diffs = Keyword.get(opts, :max_diffs_between_snapshots, 50)
    max_hours = Keyword.get(opts, :max_hours_between_snapshots, 24)

    last_snapshot =
      from(v in RepresentationVersion,
        where: v.representation_id == ^representation.id,
        where: v.version_type == "snapshot",
        order_by: [desc: v.inserted_at],
        limit: 1
      )
      |> Repo.one()

    case last_snapshot do
      nil ->
        true

      snapshot ->
        hours_since = DateTime.diff(DateTime.utc_now(), snapshot.inserted_at, :hour)
        diffs_since = count_diffs_since(representation.id, snapshot.inserted_at)

        hours_since >= max_hours or diffs_since >= max_diffs
    end
  end

  defp count_diffs_since(representation_id, since) do
    from(v in RepresentationVersion,
      where: v.representation_id == ^representation_id,
      where: v.version_type == "diff",
      where: v.inserted_at > ^since,
      select: count(v.id)
    )
    |> Repo.one()
  end

  @doc """
  Updates a representation with version tracking.

  Creates a version record before updating the content.

  ## Examples

      iex> update_representation_with_version(representation, user, %{content: "new content"})
      {:ok, %Representation{}}
  """
  def update_representation_with_version(%Representation{} = representation, %User{} = user, attrs) do
    old_content = representation.content
    new_content = attrs[:content] || attrs["content"]

    # Only create version if content is changing
    if new_content && new_content != old_content do
      case update_representation(representation, attrs) do
        {:ok, updated_rep} ->
          # Create version record (async would be better in production)
          create_version(representation, user, old_content, new_content)
          {:ok, updated_rep}

        error ->
          error
      end
    else
      update_representation(representation, attrs)
    end
  end

  # ----- Public Entry Functions -----

  @doc """
  Generates an html_public representation from the markdown representation.

  The html_public representation is always unencrypted and ready for public display.

  ## Examples

      iex> generate_html_public(entry)
      {:ok, %Entry{}}

      iex> generate_html_public(entry_without_markdown)
      {:error, :no_markdown}
  """
  def generate_html_public(%Entry{} = entry) do
    # Force reload to get latest representations
    entry = Repo.preload(entry, :representations, force: true)

    # Find the markdown representation
    markdown_rep = Enum.find(entry.representations, &(&1.type == "markdown"))

    case markdown_rep do
      nil ->
        {:error, :no_markdown}

      %{content: nil} ->
        {:error, :no_markdown}

      %{content: content} ->
        # Generate HTML from markdown
        html_content = generate_html_from_markdown(content)

        # Find or create the html_public representation
        existing_html_public = Enum.find(entry.representations, &(&1.type == "html_public"))

        result = if existing_html_public do
          # Update existing html_public representation
          existing_html_public
          |> Representation.changeset(%{content: html_content, encrypted: false})
          |> Repo.update()
        else
          # Create new html_public representation
          %Representation{}
          |> Representation.changeset(%{
            type: "html_public",
            content: html_content,
            encrypted: false,
            entry_id: entry.id
          })
          |> Repo.insert()
        end

        case result do
          {:ok, _rep} ->
            # Reload entry with representations
            {:ok, Repo.preload(entry, :representations, force: true)}

          error ->
            error
        end
    end
  end

  # Simple markdown to HTML conversion
  # In production, you'd use a proper library like Earmark with sanitization
  defp generate_html_from_markdown(markdown) when is_binary(markdown) do
    # Basic conversion - in production use Earmark + HtmlSanitizeEx
    html = markdown
    |> String.replace(~r/^### (.+)$/m, "<h3>\\1</h3>")
    |> String.replace(~r/^## (.+)$/m, "<h2>\\1</h2>")
    |> String.replace(~r/^# (.+)$/m, "<h1>\\1</h1>")
    |> String.replace(~r/\*\*(.+?)\*\*/, "<strong>\\1</strong>")
    |> String.replace(~r/\*(.+?)\*/, "<em>\\1</em>")
    |> String.replace(~r/\n\n/, "</p><p>")
    # Basic sanitization - remove script tags
    |> String.replace(~r/<script[^>]*>.*?<\/script>/is, "")
    |> String.replace(~r/<script[^>]*>/i, "")
    |> String.replace(~r/<\/script>/i, "")

    # Wrap in article tag
    ~s(<article class="prose prose-lg mx-auto"><p>#{html}</p></article>)
  end

  @doc """
  Makes an entry public.

  Sets entry.public to true and ensures html_public representation exists.
  Requires the user to have a username set.

  ## Examples

      iex> make_entry_public(entry)
      {:ok, %Entry{public: true}}

      iex> make_entry_public(entry_without_content)
      {:error, :no_content}

      iex> make_entry_public(entry_with_user_without_username)
      {:error, :no_username}
  """
  def make_entry_public(%Entry{} = entry) do
    entry = Repo.preload(entry, [:representations, :user])

    cond do
      is_nil(entry.user.username) ->
        {:error, :no_username}

      Enum.empty?(entry.representations) ->
        {:error, :no_content}

      true ->
        # Generate html_public if needed
        case generate_html_public(entry) do
          {:ok, entry} ->
            # Set entry to public
            entry
            |> Entry.changeset(%{public: true})
            |> Repo.update()
            |> case do
              {:ok, updated_entry} ->
                {:ok, Repo.preload(updated_entry, :representations, force: true)}

              error ->
                error
            end

          {:error, :no_markdown} ->
            {:error, :no_content}

          error ->
            error
        end
    end
  end

  @doc """
  Makes an entry private.

  Sets entry.public to false. Keeps the html_public representation for quick re-publish.

  ## Examples

      iex> make_entry_private(entry)
      {:ok, %Entry{public: false}}
  """
  def make_entry_private(%Entry{} = entry) do
    entry
    |> Entry.changeset(%{public: false})
    |> Repo.update()
  end

  @doc """
  Gets a public entry by username and public_id.

  Returns nil if the entry is not public or doesn't exist.
  Username lookup is case-insensitive.

  ## Examples

      iex> get_public_entry("johndoe", "abc123")
      %Entry{}

      iex> get_public_entry("johndoe", "nonexistent")
      nil
  """
  def get_public_entry(username, public_id) when is_binary(username) and is_binary(public_id) do
    query = from e in Entry,
      join: u in assoc(e, :user),
      where: fragment("lower(?)", u.username) == ^String.downcase(username),
      where: e.public_id == ^public_id,
      where: e.public == true,
      preload: [:representations, :user]

    Repo.one(query)
  end

  @doc """
  Lists all public entries for a user.

  ## Options

    * `:limit` - Maximum number of entries to return (default: 20)
    * `:offset` - Number of entries to skip (default: 0)

  ## Examples

      iex> list_public_entries(user)
      [%Entry{}, ...]

      iex> list_public_entries(user, limit: 10, offset: 0)
      [%Entry{}, ...]
  """
  def list_public_entries(%User{} = user, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)

    from(e in Entry,
      where: e.user_id == ^user.id,
      where: e.public == true,
      order_by: [desc: e.inserted_at],
      limit: ^limit,
      offset: ^offset,
      preload: [:representations]
    )
    |> Repo.all()
  end

  @doc """
  Returns the public URL for an entry.

  Returns nil if the entry is not public or the user has no username.

  ## Examples

      iex> public_entry_url(public_entry)
      "/johndoe/abc123"

      iex> public_entry_url(private_entry)
      nil
  """
  def public_entry_url(%Entry{public: false}), do: nil

  def public_entry_url(%Entry{} = entry) do
    entry = Repo.preload(entry, :user)

    case entry.user.username do
      nil -> nil
      username -> "/#{username}/#{entry.public_id}"
    end
  end

  @doc """
  Gets a preview of what will be published for an entry.

  Returns the public URL preview and list of assets that would be published.

  ## Examples

      iex> get_publish_preview(entry)
      {:ok, %{public_url_preview: "/user/abc", assets: [...], asset_count: 2}}
  """
  def get_publish_preview(%Entry{} = entry) do
    entry = Repo.preload(entry, [:user, :assets])

    url_preview = case entry.user.username do
      nil -> "/#{entry.public_id}"
      username -> "/#{username}/#{entry.public_id}"
    end

    assets = Enum.map(entry.assets, fn asset ->
      %{
        filename: asset.filename,
        size: asset.file_size,
        mime_type: asset.mime_type
      }
    end)

    {:ok, %{
      public_url_preview: url_preview,
      assets: assets,
      asset_count: length(assets)
    }}
  end

  # ============================================
  # AUTO-PROCESSING HOOKS
  # ============================================

  @doc false
  defp trigger_auto_processing_on_create(%Entry{} = entry) do
    # Skip auto-processing in test environment (avoids hitting real APIs with inline Oban)
    if Application.get_env(:onelist, :skip_auto_processing, false) do
      :ok
    else
      do_trigger_auto_processing_on_create(entry)
    end
  end

  defp do_trigger_auto_processing_on_create(%Entry{} = entry) do
    user_id = entry.user_id

    # Check Reader auto-processing (memories, tags, summaries)
    reader_enabled = Reader.reader_enabled?(user_id)

    # Check Searcher auto-embedding for entries
    # Note: Reader handles memory embeddings separately via EmbedMemoriesWorker,
    # so we only skip Searcher if Reader is enabled AND we want to avoid double work.
    # However, they serve different purposes:
    # - Reader: extracts and embeds atomic memories
    # - Searcher: embeds the entry content itself
    # These are independent, so we check both.
    searcher_enabled = Searcher.auto_embed_on_create?(user_id)

    if reader_enabled do
      Logger.debug("Enqueueing Reader processing for entry #{entry.id}")

      case Reader.enqueue_processing(entry.id) do
        {:ok, _job} ->
          :ok

        {:error, reason} ->
          Logger.warning("Failed to enqueue Reader processing for entry #{entry.id}: #{inspect(reason)}")
      end
    end

    if searcher_enabled do
      Logger.debug("Enqueueing Searcher embedding for entry #{entry.id}")

      case Searcher.enqueue_embedding(entry.id) do
        {:ok, _job} ->
          :ok

        {:error, reason} ->
          Logger.warning("Failed to enqueue Searcher embedding for entry #{entry.id}: #{inspect(reason)}")
      end
    end

    :ok
  end

  @doc false
  defp trigger_auto_processing_on_update(%Entry{} = entry) do
    # Skip auto-processing in test environment (avoids hitting real APIs with inline Oban)
    if Application.get_env(:onelist, :skip_auto_processing, false) do
      :ok
    else
      do_trigger_auto_processing_on_update(entry)
    end
  end

  defp do_trigger_auto_processing_on_update(%Entry{} = entry) do
    user_id = entry.user_id

    # Check Reader auto-processing on update
    reader_enabled = Reader.reader_enabled_on_update?(user_id)

    # Check Searcher auto-embedding on update
    searcher_enabled = Searcher.auto_embed_on_update?(user_id)

    if reader_enabled do
      Logger.debug("Enqueueing Reader processing for updated entry #{entry.id}")

      case Reader.enqueue_processing(entry.id) do
        {:ok, _job} ->
          :ok

        {:error, reason} ->
          Logger.warning("Failed to enqueue Reader processing for entry #{entry.id}: #{inspect(reason)}")
      end
    end

    if searcher_enabled do
      Logger.debug("Enqueueing Searcher embedding for updated entry #{entry.id}")

      case Searcher.enqueue_embedding(entry.id) do
        {:ok, _job} ->
          :ok

        {:error, reason} ->
          Logger.warning("Failed to enqueue Searcher embedding for entry #{entry.id}: #{inspect(reason)}")
      end
    end

    :ok
  end
end
