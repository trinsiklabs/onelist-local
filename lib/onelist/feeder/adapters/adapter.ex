defmodule Onelist.Feeder.Adapters.Adapter do
  @moduledoc """
  Behaviour for Feeder Agent source adapters.

  All source adapters (RSS, Evernote, Notion, etc.) implement this common interface
  to provide a unified way to fetch and convert external content into Onelist entries.

  ## Implementing an Adapter

  ```elixir
  defmodule Onelist.Feeder.Adapters.MySource do
    @behaviour Onelist.Feeder.Adapters.Adapter

    @impl true
    def source_type, do: "my_source"

    @impl true
    def supports_continuous_sync?, do: true

    @impl true
    def supports_one_time_import?, do: false

    @impl true
    def validate_credentials(credentials) do
      if Map.has_key?(credentials, "api_key") do
        :ok
      else
        {:error, :missing_api_key}
      end
    end

    # ... implement other callbacks
  end
  ```
  """

  @type credentials :: map()
  @type sync_cursor :: map()
  @type import_options :: map()
  @type source_item :: map()
  @type entry_attrs :: map()
  @type asset_spec :: map()
  @type sync_result :: {:ok, [source_item()], sync_cursor()} | {:error, term()}
  @type import_stream :: {:ok, Enumerable.t()} | {:error, term()}

  # ============================================
  # REQUIRED CALLBACKS
  # ============================================

  @doc """
  Returns the source type identifier (e.g., "rss", "evernote", "notion").
  """
  @callback source_type() :: String.t()

  @doc """
  Returns true if this adapter supports continuous sync (API/webhook-based).
  """
  @callback supports_continuous_sync?() :: boolean()

  @doc """
  Returns true if this adapter supports one-time import (file-based).
  """
  @callback supports_one_time_import?() :: boolean()

  @doc """
  Validate credentials structure and optionally test connection.
  Returns :ok if valid, or {:error, reason} if invalid.
  """
  @callback validate_credentials(credentials()) :: :ok | {:error, term()}

  @doc """
  Convert a source item to Onelist entry attributes.
  Returns a map ready to be passed to Entries.create_entry/2.
  """
  @callback to_entry(source_item(), user_id :: String.t()) :: entry_attrs()

  @doc """
  Extract asset specifications from a source item.
  Returns a list of maps with :url, :filename, :mime_type, etc.
  """
  @callback extract_assets(source_item()) :: [asset_spec()]

  @doc """
  Extract tags from a source item.
  Returns a list of tag names/strings.
  """
  @callback extract_tags(source_item()) :: [String.t()]

  @doc """
  Get source-specific metadata to store with the entry.
  """
  @callback source_metadata(source_item()) :: map()

  # ============================================
  # OPTIONAL CALLBACKS
  # ============================================

  @doc """
  Fetch items since last sync (for continuous sync).
  Returns new items and updated cursor for next sync.
  Only required if supports_continuous_sync?() returns true.
  """
  @callback fetch_changes(credentials(), sync_cursor(), import_options()) :: sync_result()

  @doc """
  Parse an export file and return a stream of items (for one-time import).
  Only required if supports_one_time_import?() returns true.
  """
  @callback parse_export(file_path :: String.t(), import_options()) :: import_stream()

  @doc """
  Convert content to markdown.
  Optional - default implementation passes through as-is.
  """
  @callback convert_content(source_item()) :: {:ok, String.t()} | {:error, term()}

  @optional_callbacks [fetch_changes: 3, parse_export: 2, convert_content: 1]

  # ============================================
  # DEFAULT IMPLEMENTATIONS
  # ============================================

  @doc """
  Default content conversion - returns content as-is if it's markdown-like.
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour Onelist.Feeder.Adapters.Adapter

      @impl true
      def convert_content(source_item) do
        {:ok, source_item["content"] || source_item[:content] || ""}
      end

      defoverridable convert_content: 1
    end
  end
end
