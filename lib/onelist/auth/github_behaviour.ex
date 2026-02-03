defmodule Onelist.Auth.GithubBehaviour do
  @moduledoc """
  Behavior for GitHub API interactions.
  This defines the contract for the GitHub API implementation.
  """

  @doc """
  Gets the GitHub user profile for the given token.
  """
  @callback get_user(binary()) :: {:ok, map()} | {:error, binary()}

  @doc """
  Gets the user's email addresses from GitHub API.
  """
  @callback get_user_emails(binary()) :: {:ok, list(map())} | {:error, binary()}

  @doc """
  Refreshes an OAuth token.
  """
  @callback refresh_token(binary(), binary(), binary()) :: {:ok, map()} | {:error, binary()}
end
