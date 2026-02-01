defmodule Onelist.Auth.AppleBehaviour do
  @moduledoc """
  Behavior for Apple API interactions.
  This defines the contract for the Apple ID authentication implementation.
  """
  
  @doc """
  Verifies an Apple ID token.
  """
  @callback verify_token(binary(), binary()) :: {:ok, map()} | {:error, binary()}
  
  @doc """
  Verifies an Apple ID token using a simpler interface.
  """
  @callback verify_id_token(binary()) :: {:ok, map()} | {:error, binary()}
  
  @doc """
  Extracts user name information from the auth extra data.
  """
  @callback extract_user_name(map()) :: binary() | nil
  
  @doc """
  Determines if an email is a private relay email.
  """
  @callback is_private_email?(map()) :: boolean()
end 