defmodule Onelist.Feeder.Converters.Converter do
  @moduledoc """
  Behaviour for format converters.

  Converters transform content from various formats (HTML, ENML, Notion blocks, etc.)
  into Markdown suitable for Onelist entries.

  ## Implementing a Converter

  ```elixir
  defmodule Onelist.Feeder.Converters.MyFormatConverter do
    @behaviour Onelist.Feeder.Converters.Converter

    @impl true
    def supported_formats, do: ["myformat"]

    @impl true
    def convert(content, opts) do
      # Transform content to markdown
      {:ok, markdown}
    end
  end
  ```
  """

  @type content :: String.t() | map()
  @type options :: keyword()
  @type conversion_result :: {:ok, String.t()} | {:error, term()}

  @doc """
  Returns list of format names this converter handles.
  """
  @callback supported_formats() :: [String.t()]

  @doc """
  Convert content to markdown.

  ## Options

  Common options:
  - `:preserve_links` - Keep original URLs instead of converting to relative (default: true)
  - `:include_metadata` - Include source metadata as YAML frontmatter (default: false)
  - `:max_length` - Truncate output to this length (default: nil)

  ## Returns

  - `{:ok, markdown}` - Successfully converted markdown string
  - `{:error, reason}` - Conversion failed with reason
  """
  @callback convert(content(), options()) :: conversion_result()

  @doc """
  Optional: Extract embedded assets from content.
  Returns list of asset specifications found in the content.
  """
  @callback extract_embedded_assets(content()) :: [map()]

  @optional_callbacks [extract_embedded_assets: 1]
end
