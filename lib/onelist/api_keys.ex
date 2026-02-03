defmodule Onelist.ApiKeys do
  @moduledoc """
  The ApiKeys context.

  This module handles all operations related to API key management
  for external API access.
  """

  import Ecto.Query
  alias Onelist.Repo
  alias Onelist.ApiKeys.ApiKey
  alias Onelist.Accounts.User
  alias Onelist.Security

  @key_prefix "ol_"
  @key_length 32

  # ---- API Key CRUD ----

  @doc """
  Creates an API key for a user.

  Returns `{:ok, %{api_key: api_key, raw_key: raw_key}}` where `raw_key`
  is the full API key that should be shown to the user once.

  ## Examples

      iex> create_api_key(user, %{name: "My API Key"})
      {:ok, %{api_key: %ApiKey{}, raw_key: "ol_..."}}

      iex> create_api_key(user, %{name: ""})
      {:error, %Ecto.Changeset{}}
  """
  def create_api_key(%User{} = user, attrs) do
    # Generate the raw API key
    raw_key = generate_raw_key()
    key_hash = hash_key(raw_key)
    prefix = extract_prefix(raw_key)

    # Ensure all keys are strings for the changeset (Ecto prefers string keys)
    api_key_attrs =
      attrs
      |> Enum.into(%{}, fn
        {k, v} when is_atom(k) -> {Atom.to_string(k), v}
        {k, v} -> {k, v}
      end)
      |> Map.put("key_hash", key_hash)
      |> Map.put("prefix", prefix)

    result =
      %ApiKey{user_id: user.id}
      |> ApiKey.changeset(api_key_attrs)
      |> Repo.insert()

    case result do
      {:ok, api_key} -> {:ok, %{api_key: api_key, raw_key: raw_key}}
      error -> error
    end
  end

  @doc """
  Gets an API key by id.

  ## Examples

      iex> get_api_key("uuid")
      %ApiKey{}

      iex> get_api_key("nonexistent")
      nil
  """
  def get_api_key(id) when is_binary(id) do
    Repo.get(ApiKey, id)
  end

  @doc """
  Gets an API key by the raw key string.

  Returns nil if the key is invalid, revoked, or expired.

  ## Examples

      iex> get_api_key_by_key("ol_...")
      %ApiKey{}

      iex> get_api_key_by_key("invalid")
      nil
  """
  def get_api_key_by_key(raw_key) when is_binary(raw_key) do
    key_hash = hash_key(raw_key)

    api_key =
      Repo.one(
        from k in ApiKey,
          where:
            k.key_hash == ^key_hash and
              is_nil(k.revoked_at) and
              (is_nil(k.expires_at) or k.expires_at > ^DateTime.utc_now())
      )

    api_key
  end

  @doc """
  Lists all API keys for a user.

  ## Options

    * `:include_revoked` - Include revoked keys (default: false)

  ## Examples

      iex> list_user_api_keys(user)
      [%ApiKey{}, ...]

      iex> list_user_api_keys(user, include_revoked: true)
      [%ApiKey{}, ...]
  """
  def list_user_api_keys(%User{} = user, opts \\ []) do
    include_revoked = Keyword.get(opts, :include_revoked, false)

    query =
      from k in ApiKey,
        where: k.user_id == ^user.id,
        order_by: [desc: k.inserted_at]

    query =
      if include_revoked do
        query
      else
        where(query, [k], is_nil(k.revoked_at))
      end

    Repo.all(query)
  end

  @doc """
  Revokes an API key.

  ## Examples

      iex> revoke_api_key(api_key)
      {:ok, %ApiKey{}}

      iex> revoke_api_key(already_revoked_key)
      {:error, :already_revoked}
  """
  def revoke_api_key(%ApiKey{} = api_key) do
    if ApiKey.revoked?(api_key) do
      {:error, :already_revoked}
    else
      api_key
      |> ApiKey.revoke_changeset()
      |> Repo.update()
    end
  end

  @doc """
  Validates an API key and returns the key if valid.

  ## Examples

      iex> validate_api_key("ol_...")
      {:ok, %ApiKey{}}

      iex> validate_api_key("invalid")
      {:error, :invalid_key}

      iex> validate_api_key("ol_revoked_key")
      {:error, :revoked}
  """
  def validate_api_key(raw_key) when is_binary(raw_key) do
    key_hash = hash_key(raw_key)

    case Repo.one(from k in ApiKey, where: k.key_hash == ^key_hash) do
      nil ->
        {:error, :invalid_key}

      %ApiKey{} = api_key ->
        cond do
          ApiKey.revoked?(api_key) -> {:error, :revoked}
          ApiKey.expired?(api_key) -> {:error, :expired}
          true -> {:ok, api_key}
        end
    end
  end

  @doc """
  Updates the last_used_at timestamp for an API key.

  ## Examples

      iex> touch_api_key(api_key)
      {:ok, %ApiKey{}}
  """
  def touch_api_key(%ApiKey{} = api_key) do
    api_key
    |> ApiKey.touch_changeset()
    |> Repo.update()
  end

  @doc """
  Deletes an API key.

  ## Examples

      iex> delete_api_key(api_key)
      {:ok, %ApiKey{}}
  """
  def delete_api_key(%ApiKey{} = api_key) do
    Repo.delete(api_key)
  end

  # ---- Private Functions ----

  defp generate_raw_key do
    random_part = Security.generate_token(@key_length)
    @key_prefix <> random_part
  end

  defp hash_key(raw_key) do
    Security.hash_token(raw_key)
  end

  defp extract_prefix(raw_key) do
    raw_key
    |> String.replace_prefix(@key_prefix, "")
    |> String.slice(0, 8)
  end
end
