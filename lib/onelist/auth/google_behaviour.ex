defmodule Onelist.Auth.GoogleBehaviour do
  @moduledoc """
  Defines the expected behaviour for Google OAuth authentication.
  """

  @callback get_user(token :: String.t()) ::
              {:ok, map()} | {:error, String.t()}

  @callback verify_id_token(token :: String.t(), client_id :: String.t()) ::
              {:ok, map()} | {:error, String.t()}

  @callback refresh_token(
              refresh_token :: String.t(),
              client_id :: String.t(),
              client_secret :: String.t()
            ) ::
              {:ok, map()} | {:error, String.t()}

  @callback get_user_profile(token :: String.t()) ::
              {:ok, map()} | {:error, String.t()}
end
