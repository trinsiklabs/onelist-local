defmodule OnelistWeb.SessionLive.SessionMenuComponent do
  use Phoenix.LiveComponent
  import Phoenix.Component
  import Phoenix.LiveView.JS
  
  @doc """
  A component that renders a user menu for authenticated users.
  
  ## Examples
  
      <.live_component
        module={OnelistWeb.SessionLive.SessionMenuComponent}
        id="session-menu"
        current_user={@current_user}
      />
  """
  
  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    {:ok, socket}
  end
  
  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="user-menu-wrapper">
      <%= if @current_user do %>
        <div data-test-id="user-menu" class="relative">
          <button
            data-test-id="user-menu-button"
            phx-click={toggle(to: "#user-menu-dropdown")}
            class="flex items-center"
          >
            <span class="text-sm mr-1"><%= @current_user.email %></span>
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4">
              <path stroke-linecap="round" stroke-linejoin="round" d="m19.5 8.25-7.5 7.5-7.5-7.5" />
            </svg>
          </button>
          
          <div id="user-menu-dropdown" class="hidden absolute right-0 mt-2 w-48 bg-white rounded-md shadow-lg py-1 z-10">
            <ul class="py-1">
              <li>
                <a href="/account/settings" class="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-100">
                  Account Settings
                </a>
              </li>
              <li>
                <a href="/account/sessions" data-test-id="manage-sessions-link" class="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-100">
                  Manage Sessions
                </a>
              </li>
              <li>
                <a href="/logout" data-test-id="logout-link" class="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-100">
                  Sign out
                </a>
              </li>
            </ul>
          </div>
        </div>
      <% else %>
        <div class="hidden"><!-- Empty div when not authenticated --></div>
      <% end %>
    </div>
    """
  end
end 