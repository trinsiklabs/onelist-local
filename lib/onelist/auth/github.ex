defmodule Onelist.Auth.Github do
  @moduledoc """
  Handles GitHub-specific authentication operations.

  This module implements GitHub OAuth authentication flow and user profile retrieval.
  This is defined as a behaviour for mocking in tests.
  """

  # Define that this module implements the GithubBehaviour
  @behaviour Onelist.Auth.GithubBehaviour

  @doc """
  Retrieves user information from GitHub using an access token.

  ## Examples

      iex> get_user("gho_12345abcdef")
      {:ok, %{"id" => 123456, "login" => "username", "email" => "user@example.com", ...}}
      
      iex> get_user("invalid_token")
      {:error, "Invalid token"}
  """
  @impl Onelist.Auth.GithubBehaviour
  def get_user(token) when is_binary(token) do
    # Get the configured GitHub API module (will be the mock in tests)
    github_api = Application.get_env(:onelist, :github_api, __MODULE__)

    if github_api != __MODULE__ do
      # We're in a test environment, use the mock
      github_api.get_user(token)
    else
      # We're in production, use the real implementation
      get_user_impl(token)
    end
  end

  # Private implementation for production
  defp get_user_impl(token) do
    # This would make an API call to GitHub to verify the token
    # For now, we'll just implement a simple API call to GitHub user endpoint
    with {:ok, response} <- make_github_api_request("https://api.github.com/user", token),
         {:ok, user_data} <- Jason.decode(response.body),
         {:ok, emails_response} <-
           make_github_api_request("https://api.github.com/user/emails", token),
         {:ok, emails} <- Jason.decode(emails_response.body) do
      # Find primary email that is verified
      primary_email =
        Enum.find(emails, fn email ->
          Map.get(email, "primary") == true && Map.get(email, "verified") == true
        end)

      # If we found a primary email, use it
      user_data =
        if primary_email do
          Map.put(user_data, "email", primary_email["email"])
        else
          user_data
        end

      {:ok, user_data}
    else
      {:error, %Jason.DecodeError{}} -> {:error, "Invalid response format"}
      {:error, reason} -> {:error, reason}
      _ -> {:error, "Unknown error"}
    end
  end

  @doc """
  Refreshes a GitHub OAuth token.

  ## Examples

      iex> refresh_token("refresh_token", "client_id", "client_secret")
      {:ok, %{access_token: "new_token", refresh_token: "new_refresh_token", expires_in: 3600}}
      
      iex> refresh_token("invalid_token", "client_id", "client_secret")
      {:error, "Invalid refresh token"}
  """
  @impl Onelist.Auth.GithubBehaviour
  def refresh_token(refresh_token, client_id, client_secret) when is_binary(refresh_token) do
    # Get the configured GitHub API module (will be the mock in tests)
    github_api = Application.get_env(:onelist, :github_api, __MODULE__)

    if github_api != __MODULE__ do
      # We're in a test environment, use the mock
      github_api.refresh_token(refresh_token, client_id, client_secret)
    else
      # We're in production, use the real implementation
      refresh_token_impl(refresh_token, client_id, client_secret)
    end
  end

  # Private implementation for production
  # Note: GitHub doesn't support refresh tokens in the traditional OAuth 2.0 way.
  # Their tokens are long-lived, so we just return an error.
  defp refresh_token_impl(_refresh_token, _client_id, _client_secret) do
    {:error, "GitHub doesn't support refreshing tokens"}
  end

  # Helper function for making GitHub API requests
  defp make_github_api_request(url, token) do
    headers = [
      {"Authorization", "token #{token}"},
      {"Accept", "application/vnd.github.v3+json"}
    ]

    case HTTPoison.get(url, headers) do
      {:ok, %{status_code: 200} = response} -> {:ok, response}
      {:ok, %{status_code: 401}} -> {:error, "Unauthorized"}
      {:ok, %{status_code: 403}} -> {:error, "Forbidden"}
      {:ok, %{status_code: 404}} -> {:error, "Not found"}
      {:ok, response} -> {:error, "GitHub API error: #{response.status_code}"}
      {:error, reason} -> {:error, "HTTP error: #{inspect(reason)}"}
    end
  end

  @impl Onelist.Auth.GithubBehaviour
  def get_user_emails(token) do
    get_user_emails_impl(token)
  end

  defp get_user_emails_impl(_token) do
    # TODO: In production, this should make an HTTP request to GitHub API
    # For now, return a mock response for testing
    {:ok,
     [
       %{
         "email" => "github_user@example.com",
         "verified" => true,
         "primary" => true
       }
     ]}
  end
end
