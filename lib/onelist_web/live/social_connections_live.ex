defmodule OnelistWeb.SocialConnectionsLive do
  @moduledoc """
  LiveView for managing connected social accounts.
  Allows users to view, add, and remove social connections.
  """
  
  use OnelistWeb, :live_view
  
  alias Onelist.Accounts
  
  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    social_accounts = Accounts.list_social_accounts(user)
    
    {:ok, assign(socket,
      page_title: "Social Connections",
      social_accounts: social_accounts
    )}
  end
  
  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8">
      <h1 class="text-2xl font-semibold mb-6">Connected Accounts</h1>
      
      <div class="bg-blue-50 border-l-4 border-blue-400 p-4 mb-6">
        <div class="flex">
          <div class="flex-shrink-0">
            <svg class="h-5 w-5 text-blue-400" viewBox="0 0 20 20" fill="currentColor">
              <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd" />
            </svg>
          </div>
          <div class="ml-3">
            <p class="text-sm text-blue-700">
              Connect your social accounts to sign in more easily.
            </p>
          </div>
        </div>
      </div>
      
      <div class="bg-white shadow overflow-hidden sm:rounded-md mb-8">
        <ul role="list" class="divide-y divide-gray-200">
          <%= if Enum.empty?(@social_accounts) do %>
            <li class="px-4 py-4 sm:px-6">
              <p class="text-gray-500 text-center py-4">
                You don't have any connected social accounts.
              </p>
            </li>
          <% else %>
            <%= for account <- @social_accounts do %>
              <li class="px-4 py-4 sm:px-6">
                <div class="flex items-center justify-between">
                  <div class="flex items-center">
                    <div class="flex-shrink-0">
                      <%= case account.provider do %>
                        <% "github" -> %>
                          <svg class="h-10 w-10 text-gray-800" viewBox="0 0 24 24" fill="currentColor">
                            <path d="M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12"/>
                          </svg>
                        <% "google" -> %>
                          <svg class="h-10 w-10 text-gray-800" viewBox="0 0 24 24" fill="currentColor">
                            <path d="M12.24 10.285V14.4h6.806c-.275 1.765-2.056 5.174-6.806 5.174-4.095 0-7.439-3.389-7.439-7.574s3.345-7.574 7.439-7.574c2.33 0 3.891.989 4.785 1.849l3.254-3.138C18.189 1.186 15.479 0 12.24 0c-6.635 0-12 5.365-12 12s5.365 12 12 12c6.926 0 11.52-4.869 11.52-11.726 0-.788-.085-1.39-.189-1.989H12.24z"/>
                          </svg>
                        <% "apple" -> %>
                          <svg class="h-10 w-10 text-gray-800" viewBox="0 0 24 24" fill="currentColor">
                            <path d="M17.569 12.6254C17.597 15.4891 20.2179 16.3841 20.247 16.3969C20.2248 16.4718 19.9355 17.4363 19.1767 18.4359C18.5373 19.2859 17.8665 20.1315 16.8428 20.1527C15.8413 20.173 15.4636 19.5955 14.3133 19.5955C13.1629 19.5955 12.7449 20.1315 11.8028 20.173C10.8179 20.2144 10.0544 19.2683 9.40547 18.4227C8.0679 16.6945 7.02856 13.5205 8.40513 11.3996C9.087 10.3527 10.2578 9.70168 11.5269 9.68045C12.4899 9.6592 13.3915 10.2991 13.9903 10.2991C14.5892 10.2991 15.6948 9.53727 16.8643 9.65402C17.2611 9.67128 18.5162 9.82861 19.3441 10.9308C19.2795 10.9713 17.5451 11.9714 17.569 12.6254ZM15.5227 7.3949C16.0601 6.75242 16.4133 5.85786 16.3031 4.9633C15.5399 4.99685 14.5915 5.46209 14.0328 6.08279C13.5368 6.62835 13.1088 7.55469 13.2401 8.41746C14.0964 8.48195 14.9657 8.0344 15.5227 7.3949Z"/>
                          </svg>
                        <% _ -> %>
                          <div class="h-10 w-10 bg-gray-200 rounded-full flex items-center justify-center">
                            <span class="text-gray-500 font-semibold"><%= String.first(account.provider) %></span>
                          </div>
                      <% end %>
                    </div>
                    <div class="ml-4">
                      <div class="text-lg font-medium text-gray-900">
                        <%= String.capitalize(account.provider) %>
                      </div>
                      <div class="text-sm text-gray-500">
                        <%= account.provider_email || account.provider_username || "Connected" %>
                      </div>
                    </div>
                  </div>
                  <button
                    phx-click="disconnect"
                    phx-value-id={account.id}
                    class="ml-2 inline-flex items-center px-3 py-2 border border-transparent text-sm leading-4 font-medium rounded-md text-red-700 bg-red-100 hover:bg-red-200 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500"
                    data-confirm="Are you sure you want to disconnect this account?"
                    data-test-id={"disconnect-#{account.provider}"}
                  >
                    Disconnect
                  </button>
                </div>
              </li>
            <% end %>
          <% end %>
        </ul>
      </div>
      
      <h2 class="text-lg font-medium text-gray-900 mb-4">Connect New Accounts</h2>
      
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
        <%= if not Enum.any?(@social_accounts, &(&1.provider == "github")) do %>
          <div class="relative rounded-lg border border-gray-300 bg-white px-6 py-5 shadow-sm flex items-center space-x-3 hover:border-gray-400 focus-within:ring-2 focus-within:ring-offset-2 focus-within:ring-indigo-500">
            <div class="flex-shrink-0">
              <svg class="h-10 w-10 text-gray-800" viewBox="0 0 24 24" fill="currentColor">
                <path d="M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12"/>
              </svg>
            </div>
            <div class="flex-1 min-w-0">
              <a href={~p"/auth/github"} class="focus:outline-none">
                <span class="absolute inset-0" aria-hidden="true"></span>
                <p class="text-sm font-medium text-gray-900">Connect GitHub</p>
                <p class="text-sm text-gray-500 truncate">Sign in with your GitHub account</p>
              </a>
            </div>
          </div>
        <% end %>
        
        <%= if not Enum.any?(@social_accounts, &(&1.provider == "google")) do %>
          <div class="relative rounded-lg border border-gray-300 bg-white px-6 py-5 shadow-sm flex items-center space-x-3 hover:border-gray-400 focus-within:ring-2 focus-within:ring-offset-2 focus-within:ring-indigo-500">
            <div class="flex-shrink-0">
              <svg class="h-10 w-10 text-gray-800" viewBox="0 0 24 24" fill="currentColor">
                <path d="M12.24 10.285V14.4h6.806c-.275 1.765-2.056 5.174-6.806 5.174-4.095 0-7.439-3.389-7.439-7.574s3.345-7.574 7.439-7.574c2.33 0 3.891.989 4.785 1.849l3.254-3.138C18.189 1.186 15.479 0 12.24 0c-6.635 0-12 5.365-12 12s5.365 12 12 12c6.926 0 11.52-4.869 11.52-11.726 0-.788-.085-1.39-.189-1.989H12.24z"/>
              </svg>
            </div>
            <div class="flex-1 min-w-0">
              <a href={~p"/auth/google"} class="focus:outline-none">
                <span class="absolute inset-0" aria-hidden="true"></span>
                <p class="text-sm font-medium text-gray-900">Connect Google</p>
                <p class="text-sm text-gray-500 truncate">Sign in with your Google account</p>
              </a>
            </div>
          </div>
        <% end %>
        
        <%= if not Enum.any?(@social_accounts, &(&1.provider == "apple")) do %>
          <div class="relative rounded-lg border border-gray-300 bg-white px-6 py-5 shadow-sm flex items-center space-x-3 hover:border-gray-400 focus-within:ring-2 focus-within:ring-offset-2 focus-within:ring-indigo-500">
            <div class="flex-shrink-0">
              <svg class="h-10 w-10 text-gray-800" viewBox="0 0 24 24" fill="currentColor">
                <path d="M17.569 12.6254C17.597 15.4891 20.2179 16.3841 20.247 16.3969C20.2248 16.4718 19.9355 17.4363 19.1767 18.4359C18.5373 19.2859 17.8665 20.1315 16.8428 20.1527C15.8413 20.173 15.4636 19.5955 14.3133 19.5955C13.1629 19.5955 12.7449 20.1315 11.8028 20.173C10.8179 20.2144 10.0544 19.2683 9.40547 18.4227C8.0679 16.6945 7.02856 13.5205 8.40513 11.3996C9.087 10.3527 10.2578 9.70168 11.5269 9.68045C12.4899 9.6592 13.3915 10.2991 13.9903 10.2991C14.5892 10.2991 15.6948 9.53727 16.8643 9.65402C17.2611 9.67128 18.5162 9.82861 19.3441 10.9308C19.2795 10.9713 17.5451 11.9714 17.569 12.6254ZM15.5227 7.3949C16.0601 6.75242 16.4133 5.85786 16.3031 4.9633C15.5399 4.99685 14.5915 5.46209 14.0328 6.08279C13.5368 6.62835 13.1088 7.55469 13.2401 8.41746C14.0964 8.48195 14.9657 8.0344 15.5227 7.3949Z"/>
              </svg>
            </div>
            <div class="flex-1 min-w-0">
              <a href={~p"/auth/apple"} class="focus:outline-none">
                <span class="absolute inset-0" aria-hidden="true"></span>
                <p class="text-sm font-medium text-gray-900">Connect Apple</p>
                <p class="text-sm text-gray-500 truncate">Sign in with your Apple ID</p>
              </a>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
  
  @impl true
  def handle_event("disconnect", %{"id" => id}, socket) do
    social_account = Enum.find(socket.assigns.social_accounts, &(&1.id == id))
    
    if social_account do
      case Accounts.delete_social_account(social_account) do
        {:ok, _} ->
          # Refresh the list of social accounts
          social_accounts = Accounts.list_social_accounts(socket.assigns.current_user)
          
          {:noreply, 
            socket
            |> put_flash(:info, "#{String.capitalize(social_account.provider)} account disconnected.")
            |> assign(:social_accounts, social_accounts)
          }
          
        {:error, _} ->
          {:noreply, 
            socket
            |> put_flash(:error, "Failed to disconnect account. Please try again.")
          }
      end
    else
      {:noreply, socket}
    end
  end
end 