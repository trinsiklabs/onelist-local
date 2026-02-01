defmodule Onelist.Auth.GoogleAuth do
  @moduledoc """
  Behavior for Google authentication operations.
  
  This module defines the callback functions required for Google authentication,
  particularly OAuth token verification and user data retrieval.
  """
  
  @doc """
  Verifies a Google ID token (JWT) against Google's public keys.
  """
  @callback verify_id_token(token :: binary, client_id :: binary) :: {:ok, map} | {:error, binary}
  
  @doc """
  Fetches user profile information from Google using an access token.
  """
  @callback get_user_profile(token :: binary) :: {:ok, map} | {:error, binary}
  
  @doc """
  Refreshes an expired access token using a refresh token.
  """
  @callback refresh_token(refresh_token :: binary, client_id :: binary, client_secret :: binary) :: 
    {:ok, map} | {:error, binary}
end 