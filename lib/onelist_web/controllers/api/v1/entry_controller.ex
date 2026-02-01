defmodule OnelistWeb.Api.V1.EntryController do
  @moduledoc """
  API controller for Entry CRUD operations.
  """
  use OnelistWeb, :controller

  alias Onelist.Entries

  action_fallback OnelistWeb.Api.V1.FallbackController

  @default_per_page 20
  @max_per_page 100

  @doc """
  Lists entries for the authenticated user with pagination and filtering.

  Query parameters:
  - page: Page number (default: 1)
  - per_page: Items per page (default: 20, max: 100)
  - entry_type: Filter by entry type (note, memory, photo, video)
  - source_type: Filter by source type (manual, web_clip, api)
  - public: Filter by public status (true/false)
  """
  def index(conn, params) do
    user = conn.assigns.current_user
    {page, per_page} = parse_pagination(params)
    offset = (page - 1) * per_page

    filter_opts =
      []
      |> maybe_add_filter(:entry_type, params["entry_type"])
      |> maybe_add_filter(:source_type, params["source_type"])
      |> maybe_add_filter(:public, parse_boolean(params["public"]))

    entries = Entries.list_user_entries(user, filter_opts ++ [limit: per_page, offset: offset])
    total = Entries.count_user_entries(user, filter_opts)
    total_pages = ceil(total / per_page)

    meta = %{
      total: total,
      page: page,
      per_page: per_page,
      total_pages: total_pages
    }

    render(conn, :index, entries: entries, meta: meta)
  end

  @doc """
  Shows a single entry with its representations.
  """
  def show(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Entries.get_user_entry(user, id) do
      nil ->
        {:error, :not_found}

      entry ->
        entry = Onelist.Repo.preload(entry, :representations)
        render(conn, :show, entry: entry)
    end
  end

  @doc """
  Creates a new entry for the authenticated user.

  Expected params:
  - entry.title: Entry title (optional)
  - entry.entry_type: Entry type (required: note, memory, photo, video)
  - entry.source_type: Source type (optional: manual, web_clip, api)
  - entry.public: Public status (optional, default: false)
  - entry.content: Initial content for markdown representation (optional)
  - entry.content_created_at: Content creation timestamp (optional)
  - entry.metadata: Additional metadata (optional)
  """
  def create(conn, %{"entry" => entry_params}) do
    user = conn.assigns.current_user

    # Extract content separately for representation
    {content, entry_attrs} = Map.pop(entry_params, "content")

    # Default source_type to "api" if not provided
    entry_attrs = Map.put_new(entry_attrs, "source_type", "api")

    with {:ok, entry} <- Entries.create_entry(user, entry_attrs),
         {:ok, entry} <- maybe_add_content(entry, content) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/v1/entries/#{entry.id}")
      |> render(:create, entry: entry)
    end
  end

  def create(_conn, _params) do
    {:error, :bad_request, "Missing entry parameters"}
  end

  @doc """
  Updates an existing entry.

  Expected params:
  - entry.title: Entry title (optional)
  - entry.entry_type: Entry type (optional)
  - entry.source_type: Source type (optional)
  - entry.public: Public status (optional)
  - entry.content: Update markdown representation content (optional)
  - entry.metadata: Additional metadata (optional)
  """
  def update(conn, %{"id" => id, "entry" => entry_params}) do
    user = conn.assigns.current_user

    case Entries.get_user_entry(user, id) do
      nil ->
        {:error, :not_found}

      entry ->
        # Extract content separately for representation update
        {content, entry_attrs} = Map.pop(entry_params, "content")

        with {:ok, updated_entry} <- Entries.update_entry(entry, entry_attrs),
             {:ok, updated_entry} <- maybe_update_content(updated_entry, content) do
          render(conn, :update, entry: updated_entry)
        end
    end
  end

  def update(_conn, %{"id" => _id}) do
    {:error, :bad_request, "Missing entry parameters"}
  end

  @doc """
  Deletes an entry.
  """
  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Entries.get_user_entry(user, id) do
      nil ->
        {:error, :not_found}

      entry ->
        with {:ok, _entry} <- Entries.delete_entry(entry) do
          send_resp(conn, :no_content, "")
        end
    end
  end

  # Private helpers

  defp parse_pagination(params) do
    page = parse_positive_int(params["page"], 1)
    per_page = parse_positive_int(params["per_page"], @default_per_page)
    per_page = min(per_page, @max_per_page)

    {page, per_page}
  end

  defp parse_positive_int(nil, default), do: default
  defp parse_positive_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} when int > 0 -> int
      _ -> default
    end
  end
  defp parse_positive_int(_, default), do: default

  defp parse_boolean("true"), do: true
  defp parse_boolean("false"), do: false
  defp parse_boolean(_), do: nil

  defp maybe_add_filter(opts, _key, nil), do: opts
  defp maybe_add_filter(opts, key, value), do: Keyword.put(opts, key, value)

  defp maybe_add_content(entry, nil), do: {:ok, entry}
  defp maybe_add_content(entry, "") do
    entry = Onelist.Repo.preload(entry, :representations)
    {:ok, entry}
  end
  defp maybe_add_content(entry, content) when is_binary(content) do
    case Entries.add_representation(entry, %{type: "markdown", content: content}) do
      {:ok, _rep} ->
        entry = Onelist.Repo.preload(entry, :representations)
        {:ok, entry}

      error ->
        error
    end
  end

  defp maybe_update_content(entry, nil), do: {:ok, entry}
  defp maybe_update_content(entry, content) when is_binary(content) do
    case Entries.get_primary_representation(entry) do
      nil ->
        # No existing representation, create one
        maybe_add_content(entry, content)

      rep ->
        case Entries.update_representation(rep, %{content: content}) do
          {:ok, _rep} ->
            entry = Onelist.Repo.preload(entry, :representations, force: true)
            {:ok, entry}

          error ->
            error
        end
    end
  end
end
