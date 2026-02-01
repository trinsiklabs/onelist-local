defmodule OnelistWeb.Auth.LinkAccountLive do
  @moduledoc """
  LiveView for handling account linking when a user tries to sign in
  with a social provider that matches an existing email.
  """
  
  use OnelistWeb, :live_view
  
  alias Onelist.Accounts
  alias Onelist.Sessions
  
  @impl true
  def mount(_params, session, socket) do
    # Get the pending social link data from the session
    pending_link = session["pending_social_link"]
    
    if pending_link do
      # Convert string keys to atoms
      pending_link = for {key, val} <- pending_link, into: %{} do
        {String.to_existing_atom(key), val}
      end
      
      # Get the user with matching email
      email = pending_link.user_params["email"]
      user = Accounts.get_user_by_email(email)
      
      socket = assign(socket,
        page_title: "Link Account",
        email: email,
        provider: pending_link.provider,
        provider_id: pending_link.provider_id,
        user_params: pending_link.user_params,
        existing_user: user,
        action: nil
      )
      
      {:ok, socket}
    else
      # No pending social link, redirect to login
      {:ok, 
        socket
        |> put_flash(:error, "No account to link. Please try signing in again.")
        |> redirect(to: ~p"/login")
      }
    end
  end
  
  @impl true
  def render(assigns) do
    ~H"""
    <div class="link-account-container">
      <h1 class="text-2xl font-semibold mb-4">Connect Accounts</h1>
      
      <div class="bg-yellow-50 border-l-4 border-yellow-400 p-4 mb-6">
        <div class="flex">
          <div class="flex-shrink-0">
            <svg class="h-5 w-5 text-yellow-400" viewBox="0 0 20 20" fill="currentColor">
              <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd" />
            </svg>
          </div>
          <div class="ml-3">
            <p class="text-sm text-yellow-700">
              We found an existing account with the email <strong><%= @email %></strong>
            </p>
          </div>
        </div>
      </div>
      
      <p class="mb-4">
        You're trying to sign in with <strong><%= String.capitalize(@provider) %></strong> using an email
        that's already associated with an existing account. What would you like to do?
      </p>
      
      <div class="flex flex-col space-y-4 mt-6">
        <button phx-click="link-accounts" class="btn btn-primary">
          Connect to existing account
        </button>
        <p class="text-sm text-gray-600 mb-4">
          You'll need to sign in to confirm this connection.
        </p>
        
        <button phx-click="create-new-account" class="btn btn-secondary">
          Create new account
        </button>
        <p class="text-sm text-gray-600">
          This will create a separate account using your <%= String.capitalize(@provider) %> profile.
        </p>
      </div>
    </div>
    """
  end
  
  @impl true
  def handle_event("link-accounts", _params, socket) do
    # We'll need the user to sign in first to verify ownership
    # Store that we're trying to link accounts
    {:noreply,
      socket
      |> put_flash(:info, "Please sign in to link your account with #{String.capitalize(socket.assigns.provider)}.")
      |> redirect(to: ~p"/login")
    }
  end
  
  @impl true
  def handle_event("create-new-account", _params, socket) do
    %{provider: provider, provider_id: provider_id, user_params: user_params} = socket.assigns
    
    # Generate a random email if needed (shouldn't happen since we already have email)
    email = user_params["email"] || "#{provider}_#{provider_id}@example.com"
    # Make email unique by adding timestamp if needed
    email = if Accounts.get_user_by_email(email) do
      [username, domain] = String.split(email, "@")
      timestamp = :os.system_time(:millisecond)
      "#{username}+#{timestamp}@#{domain}"
    else
      email
    end
    
    # Generate a secure random password
    password = Onelist.Security.generate_token(32)
    
    # Create a new user
    {:ok, user} = Accounts.create_user(%{
      email: email,
      password: password,
      name: user_params["name"],
      email_verified: true # Consider email verified from provider
    })
    
    # Link the social account
    {:ok, _social_account} = Accounts.create_social_account(user, %{
      provider: provider,
      provider_id: provider_id,
      provider_email: user_params["email"],
      provider_username: user_params["provider_username"],
      provider_name: user_params["name"],
      avatar_url: user_params["avatar_url"],
      token_data: user_params["token_data"]
    })
    
    # Create a session for the user
    conn = Map.get(socket, :conn)
    {:ok, %{token: token}} = Sessions.create_session(user, %{
      "user_agent" => get_user_agent(conn),
      "ip_address" => get_client_ip(conn),
      "context" => "social_registration"
    })
    
    # Instead of directly manipulating the session, redirect to a controller
    # that will handle this for us
    {:noreply,
      socket
      |> clear_flash()
      |> put_flash(:info, "Account created successfully with #{String.capitalize(provider)}.")
      |> redirect(to: "/auth/complete-social-login?token=#{token}")
    }
  end
  
  # Helper functions for getting client info
  
  defp get_client_ip(conn) do
    forwarded = List.first(Plug.Conn.get_req_header(conn, "x-forwarded-for"))
    
    cond do
      forwarded && String.contains?(forwarded, ",") ->
        forwarded |> String.split(",") |> List.first() |> String.trim()
      
      forwarded ->
        String.trim(forwarded)
      
      true ->
        conn.remote_ip |> Tuple.to_list() |> Enum.join(".")
    end
  end
  
  defp get_user_agent(conn) do
    List.first(Plug.Conn.get_req_header(conn, "user-agent")) || ""
  end
end 