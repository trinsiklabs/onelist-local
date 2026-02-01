defmodule Onelist.Searcher.SearchConfig do
  @moduledoc """
  Schema for user search configuration and preferences.

  Each user can customize their embedding model, search type,
  and other parameters for the Searcher agent.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @search_types ~w(hybrid semantic keyword)
  @default_model "text-embedding-3-small"
  @default_dimensions 1536

  schema "search_configs" do
    # Model settings
    field :embedding_model, :string, default: @default_model
    field :embedding_dimensions, :integer, default: @default_dimensions

    # Search defaults
    field :default_search_type, :string, default: "hybrid"
    field :semantic_weight, :decimal, default: Decimal.new("0.7")
    field :keyword_weight, :decimal, default: Decimal.new("0.3")

    # Processing settings
    field :auto_embed_on_create, :boolean, default: true
    field :auto_embed_on_update, :boolean, default: true
    field :max_chunk_tokens, :integer, default: 500
    field :chunk_overlap_tokens, :integer, default: 50

    # Rate limiting
    field :daily_embedding_limit, :integer
    field :embeddings_today, :integer, default: 0
    field :limit_reset_at, :utc_datetime_usec

    # Enrichment settings
    field :auto_enrich_enabled, :boolean, default: true
    field :max_enrichment_tier, :integer, default: 2
    field :enrichment_settings, :map, default: %{}
    field :daily_enrichment_budget_cents, :integer
    field :spent_enrichment_today_cents, :integer, default: 0
    field :enrichment_budget_reset_at, :utc_datetime_usec

    # Reader settings
    field :auto_process_on_create, :boolean, default: true
    field :auto_process_on_update, :boolean, default: true
    field :extraction_model, :string, default: "gpt-4o-mini"
    field :reader_settings, :map, default: %{}

    belongs_to :user, Onelist.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:user_id]
  @optional_fields [
    :embedding_model,
    :embedding_dimensions,
    :default_search_type,
    :semantic_weight,
    :keyword_weight,
    :auto_embed_on_create,
    :auto_embed_on_update,
    :max_chunk_tokens,
    :chunk_overlap_tokens,
    :daily_embedding_limit,
    :embeddings_today,
    :limit_reset_at,
    :auto_enrich_enabled,
    :max_enrichment_tier,
    :enrichment_settings,
    :daily_enrichment_budget_cents,
    :spent_enrichment_today_cents,
    :enrichment_budget_reset_at,
    :auto_process_on_create,
    :auto_process_on_update,
    :extraction_model,
    :reader_settings
  ]

  @doc """
  Creates a changeset for a search configuration.
  """
  def changeset(config, attrs) do
    config
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:default_search_type, @search_types)
    |> validate_number(:semantic_weight, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> validate_number(:keyword_weight, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> validate_number(:max_chunk_tokens, greater_than: 0)
    |> validate_number(:chunk_overlap_tokens, greater_than_or_equal_to: 0)
    |> validate_number(:embedding_dimensions, greater_than: 0)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:user_id)
  end

  @doc """
  Creates a changeset for updating search configuration.
  """
  def update_changeset(config, attrs) do
    changeset(config, attrs)
  end

  @doc """
  Returns the list of valid search types.
  """
  def search_types, do: @search_types

  @doc """
  Returns the default embedding model name.
  """
  def default_model, do: @default_model

  @doc """
  Returns the default embedding dimensions.
  """
  def default_dimensions, do: @default_dimensions

  @doc """
  Returns the default enrichment settings for a specific asset type.
  """
  def default_enrichment_settings(asset_type) do
    case asset_type do
      "image" -> %{"enabled" => true, "ocr" => true, "description" => true, "max_dimension" => 4096}
      "audio" -> %{"enabled" => true, "transcribe" => true, "extract_actions" => true, "max_duration_minutes" => 120}
      "video" -> %{"enabled" => true, "extract_audio" => true, "max_duration_minutes" => 60}
      "document" -> %{"enabled" => true, "ocr" => true}
      _ -> %{"enabled" => false}
    end
  end

  @doc """
  Gets enrichment settings for a specific asset type, with defaults.
  """
  def get_enrichment_settings(%__MODULE__{enrichment_settings: settings}, asset_type) do
    Map.get(settings || %{}, asset_type, default_enrichment_settings(asset_type))
  end

  @doc """
  Returns the default reader settings.
  """
  def default_reader_settings do
    %{
      "extract_memories" => true,
      "resolve_references" => true,
      "detect_relationships" => true,
      "auto_summarize" => true,
      "auto_suggest_tags" => true,
      "max_tag_suggestions" => 5
    }
  end

  @doc """
  Gets reader settings, with defaults.
  """
  def get_reader_settings(%__MODULE__{reader_settings: settings}) do
    Map.merge(default_reader_settings(), settings || %{})
  end
end
