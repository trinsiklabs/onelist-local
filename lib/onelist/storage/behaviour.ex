defmodule Onelist.Storage.Behaviour do
  @moduledoc """
  Behaviour defining the interface for storage backends.

  All storage backends (Local, S3, GCS, etc.) must implement this behaviour
  to ensure consistent operations across different storage providers.

  ## Callbacks

  - `put/3` - Store content at the given path
  - `get/1` or `get/2` - Retrieve content from the given path
  - `delete/1` - Delete content at the given path
  - `exists?/1` - Check if content exists at the given path
  - `presigned_url/2` - Generate a presigned URL for direct access
  - `head/1` - Get metadata about content without downloading
  - `backend_id/0` - Return the backend identifier atom

  ## Example Implementation

      defmodule MyBackend do
        @behaviour Onelist.Storage.Behaviour

        @impl true
        def backend_id, do: :my_backend

        @impl true
        def put(path, content, opts \\\\ []) do
          # Store content...
          {:ok, %{size: byte_size(content), path: path}}
        end

        # ... other callbacks
      end
  """

  @type path :: String.t()
  @type content :: binary()
  @type opts :: keyword()
  @type metadata :: %{
          optional(:size) => non_neg_integer(),
          optional(:content_type) => String.t(),
          optional(:checksum) => String.t(),
          optional(:last_modified) => DateTime.t(),
          optional(:etag) => String.t(),
          optional(atom()) => any()
        }
  @type error_reason :: :not_found | :access_denied | :timeout | :network_error | term()

  @doc """
  Returns the unique identifier for this backend.

  Used for configuration lookup and mirror tracking.

  ## Examples

      iex> Onelist.Storage.Backends.Local.backend_id()
      :local

      iex> Onelist.Storage.Backends.S3.backend_id()
      :s3
  """
  @callback backend_id() :: atom()

  @doc """
  Stores content at the specified path.

  ## Options

  - `:content_type` - MIME type of the content
  - `:metadata` - Additional metadata to store with the content
  - `:checksum` - Expected SHA-256 checksum for verification

  ## Returns

  - `{:ok, metadata}` - Success with metadata including size, path, etc.
  - `{:error, reason}` - Failure with error reason
  """
  @callback put(path, content, opts) ::
              {:ok, metadata} | {:error, error_reason}

  @doc """
  Retrieves content from the specified path.

  ## Options

  - `:range` - Byte range for partial content (e.g., `{0, 1023}`)

  ## Returns

  - `{:ok, binary}` - Success with the content
  - `{:error, :not_found}` - Content does not exist
  - `{:error, reason}` - Other failure
  """
  @callback get(path) :: {:ok, binary()} | {:error, error_reason}
  @callback get(path, opts) :: {:ok, binary()} | {:error, error_reason}

  @doc """
  Deletes content at the specified path.

  ## Returns

  - `:ok` - Success (also returns :ok if content didn't exist)
  - `{:error, reason}` - Failure
  """
  @callback delete(path) :: :ok | {:error, error_reason}

  @doc """
  Checks if content exists at the specified path.

  ## Returns

  - `true` - Content exists
  - `false` - Content does not exist or error occurred
  """
  @callback exists?(path) :: boolean()

  @doc """
  Generates a presigned URL for direct access to the content.

  For backends that don't support presigned URLs (like local filesystem),
  this may return a direct path or a token-based URL.

  ## Options

  - `:expires_in` - URL expiration time in seconds (default: 3600)
  - `:method` - HTTP method the URL is valid for (:get or :put)
  - `:content_type` - Required for :put method

  ## Returns

  - `{:ok, url}` - Success with the presigned URL
  - `{:error, :not_supported}` - Backend doesn't support presigned URLs
  - `{:error, reason}` - Other failure
  """
  @callback presigned_url(path, opts) ::
              {:ok, String.t()} | {:error, error_reason}

  @doc """
  Gets metadata about content without downloading it.

  ## Returns

  - `{:ok, metadata}` - Success with metadata map
  - `{:error, :not_found}` - Content does not exist
  - `{:error, reason}` - Other failure

  ## Metadata Fields

  - `:size` - Content size in bytes
  - `:content_type` - MIME type
  - `:last_modified` - Last modification timestamp
  - `:etag` - Entity tag for caching
  - `:checksum` - Content checksum if available
  """
  @callback head(path) :: {:ok, metadata} | {:error, error_reason}

  @optional_callbacks [get: 2]
end
