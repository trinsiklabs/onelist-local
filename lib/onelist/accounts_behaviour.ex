defmodule Onelist.AccountsBehaviour do
  @moduledoc """
  Defines the behavior interface for the Accounts module.
  """
  
  @type user :: map()
  @type user_params :: map()
  @type token :: binary()
  @type reason :: atom() | binary()
  
  @callback get_user_by_email(String.t()) :: {:ok, map()} | {:error, atom()}
  @callback get_user_by_social_account(String.t(), String.t()) :: {:ok, map()} | {:error, atom()}
  @callback create_user(params :: user_params()) :: {:ok, user()} | {:error, any()}
  @callback create_social_account(user :: user(), params :: map()) :: {:ok, map()} | {:error, any()}
  @callback update_social_account(map(), String.t(), String.t(), map()) :: {:ok, map()} | {:error, atom()}
  @callback get_social_account(user_id :: binary(), provider :: binary()) :: map() | nil
  @callback verify_email(token :: binary()) :: {:ok, user()} | {:error, reason()}
  @callback change_user_password(user :: user()) :: Ecto.Changeset.t()
  @callback change_user_password(user :: user(), params :: map()) :: Ecto.Changeset.t()
  @callback create_user_with_social_account(map(), String.t(), String.t()) :: {:ok, map()} | {:error, atom()}
  @callback list_user_social_accounts(map()) :: list(map())
  @callback unlink_social_account(map(), String.t()) :: {:ok, any()} | {:error, atom()}
end 