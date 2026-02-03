defmodule Onelist.Accounts.Behaviour do
  @moduledoc """
  Behaviour specification for the Accounts context.
  """

  @callback register_user(attrs :: map()) ::
              {:ok, map()} | {:error, any()}

  @callback get_user_by_reset_token(token :: binary() | map()) ::
              {:ok, map()} | {:error, :expired | :not_found}

  @callback reset_password(token :: binary() | map(), password :: binary()) ::
              {:ok, map()} | {:error, :expired | :not_found}

  @callback verify_email(token :: binary()) ::
              {:ok, map()} | {:error, :expired_token | :invalid_token}
end
