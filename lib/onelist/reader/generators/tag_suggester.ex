defmodule Onelist.Reader.Generators.TagSuggester do
  @moduledoc """
  Generates tag suggestions for entries based on content analysis.

  Tag suggestions are stored as representations with type "tag_suggestion"
  and include confidence scores and reasoning for each suggestion.
  """

  import Ecto.Query, warn: false

  alias Onelist.{Repo, Entries, Tags}
  alias Onelist.Entries.Representation

  require Logger

  @default_max_suggestions 5

  @doc """
  Generate tag suggestions for text content.

  ## Options
    * `:max_suggestions` - Maximum number of tags to suggest (default: 5)
    * `:existing_tags` - List of existing tag names to prefer (default: [])
    * `:min_confidence` - Minimum confidence threshold (default: 0.5)

  Returns `{:ok, suggestions}` or `{:error, reason}`
  """
  def suggest(text, opts \\ []) do
    max_suggestions = Keyword.get(opts, :max_suggestions, @default_max_suggestions)
    existing_tags = Keyword.get(opts, :existing_tags, [])
    min_confidence = Keyword.get(opts, :min_confidence, 0.5)

    text = String.trim(text || "")

    if text == "" do
      {:ok, %{suggestions: [], cost_cents: 0}}
    else
      case llm_provider().suggest_tags(text,
             max_suggestions: max_suggestions,
             existing_tags: existing_tags
           ) do
        {:ok, result} ->
          filtered =
            result.suggestions
            |> Enum.filter(fn s -> s["confidence"] >= min_confidence end)
            |> Enum.take(max_suggestions)

          {:ok,
           %{
             suggestions: filtered,
             cost_cents: result.cost_cents,
             model: result.model
           }}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Generate and store tag suggestions for an entry as a representation.

  Creates or updates a "tag_suggestion" representation for the entry.
  """
  def suggest_and_store(entry_id, text, opts \\ []) do
    user_id = Keyword.get(opts, :user_id)

    with {:ok, result} <- suggest(text, opts),
         {:ok, _rep} <- store_suggestions(entry_id, result, user_id) do
      {:ok, result}
    end
  end

  @doc """
  Store tag suggestions as a representation.

  The representation contains:
  - type: "tag_suggestion"
  - metadata: %{
      "suggestions" => [...],
      "status" => "pending",
      "model" => "gpt-4o-mini",
      "cost_cents" => 0
    }
  """
  def store_suggestions(entry_id, result, user_id \\ nil) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    metadata = %{
      "suggestions" => result.suggestions,
      "status" => "pending",
      "model" => result.model,
      "cost_cents" => result.cost_cents,
      "generated_at" => now,
      "user_id" => user_id
    }

    # Check if a tag_suggestion representation already exists
    existing =
      Representation
      |> where([r], r.entry_id == ^entry_id and r.type == "tag_suggestion")
      |> Repo.one()

    if existing do
      # Update existing representation
      existing
      |> Representation.update_changeset(%{metadata: metadata})
      |> Repo.update()
    else
      # Create new representation
      %Representation{entry_id: entry_id}
      |> Representation.changeset(%{
        type: "tag_suggestion",
        content: nil,
        metadata: metadata,
        encrypted: false
      })
      |> Repo.insert()
    end
  end

  @doc """
  Get pending tag suggestions for an entry.

  Returns suggestions that haven't been accepted or rejected yet.
  """
  def get_pending_suggestions(entry_id) do
    Representation
    |> where([r], r.entry_id == ^entry_id and r.type == "tag_suggestion")
    |> Repo.one()
    |> case do
      nil ->
        {:ok, []}

      rep ->
        suggestions =
          case get_in(rep.metadata, ["suggestions"]) do
            nil -> []
            suggestions when is_list(suggestions) -> suggestions
            _ -> []
          end

        # Filter to only pending suggestions
        pending =
          Enum.filter(suggestions, fn s ->
            Map.get(s, "status", "pending") == "pending"
          end)

        {:ok, pending}
    end
  end

  @doc """
  Accept a tag suggestion and apply it to the entry.

  Marks the suggestion as accepted and creates the tag association.
  """
  def accept_suggestion(entry_id, tag_name) do
    with {:ok, rep} <- get_tag_suggestion_rep(entry_id),
         {:ok, _} <- update_suggestion_status(rep, tag_name, "accepted"),
         {:ok, entry} <- apply_tag_to_entry(entry_id, tag_name) do
      {:ok, entry}
    end
  end

  @doc """
  Reject a tag suggestion.

  Marks the suggestion as rejected so it won't be shown again.
  """
  def reject_suggestion(entry_id, tag_name) do
    with {:ok, rep} <- get_tag_suggestion_rep(entry_id),
         {:ok, _} <- update_suggestion_status(rep, tag_name, "rejected") do
      :ok
    end
  end

  @doc """
  Accept all pending tag suggestions for an entry.
  """
  def accept_all_suggestions(entry_id) do
    with {:ok, pending} <- get_pending_suggestions(entry_id) do
      results =
        Enum.map(pending, fn suggestion ->
          accept_suggestion(entry_id, suggestion["tag"])
        end)

      errors = Enum.filter(results, fn r -> match?({:error, _}, r) end)

      if Enum.any?(errors) do
        {:error, {:partial_failure, errors}}
      else
        {:ok, length(results)}
      end
    end
  end

  defp get_tag_suggestion_rep(entry_id) do
    Representation
    |> where([r], r.entry_id == ^entry_id and r.type == "tag_suggestion")
    |> Repo.one()
    |> case do
      nil -> {:error, :no_suggestions}
      rep -> {:ok, rep}
    end
  end

  defp update_suggestion_status(rep, tag_name, status) do
    suggestions = rep.metadata["suggestions"] || []

    updated_suggestions =
      Enum.map(suggestions, fn s ->
        if s["tag"] == tag_name do
          Map.put(s, "status", status)
        else
          s
        end
      end)

    updated_metadata = Map.put(rep.metadata, "suggestions", updated_suggestions)

    rep
    |> Representation.update_changeset(%{metadata: updated_metadata})
    |> Repo.update()
  end

  defp apply_tag_to_entry(entry_id, tag_name) do
    # Get the entry with its user
    entry = Entries.get_entry(entry_id) |> Repo.preload([:user])

    if entry do
      # Get or create the tag
      {:ok, tag} = Tags.get_or_create_tag(entry.user, tag_name)

      # Add tag to entry
      Tags.add_tag_to_entry(entry, tag)

      {:ok, entry}
    else
      {:error, :entry_not_found}
    end
  end

  # Returns the configured LLM provider module
  defp llm_provider do
    Application.get_env(:onelist, :reader_llm_provider, Onelist.Reader.Providers.Anthropic)
  end
end
