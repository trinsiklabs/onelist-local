defmodule Onelist.Auth.GithubAuth do
  @moduledoc """
  Behavior for GitHub authentication operations.
  
  This module defines the callback functions required for GitHub authentication,
  particularly API token verification and user data retrieval.
  """
  
  @doc """
  Verifies a GitHub access token and retrieves user information.
  """
  @callback verify_token(token :: binary) :: {:ok, map} | {:error, binary}
  
  @doc """
  Fetches user profile information from GitHub using an access token.
  """
  @callback get_user_profile(token :: binary) :: {:ok, map} | {:error, binary}
  
  @doc """
  Gets user's email addresses from GitHub using an access token.
  """
  @callback get_user_emails(token :: binary) :: {:ok, list} | {:error, binary}
end 