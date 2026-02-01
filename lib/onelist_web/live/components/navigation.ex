defmodule OnelistWeb.Navigation do
  use Phoenix.LiveComponent

  def mount(socket) do
    {:ok, assign(socket, current_user: nil, current_page: nil)}
  end

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  def render(assigns) do
    ~H"""
    <nav class="bg-white shadow" id={@id}>
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="flex justify-between h-16">
          <div class="flex">
            <div class="flex-shrink-0 flex items-center">
              <a href="/" data-test-id="nav-logo" class="text-indigo-600 text-xl font-bold">
                Onelist
              </a>
            </div>
            <div class="hidden sm:ml-6 sm:flex sm:space-x-8">
              <%= nav_link(%{text: "Home", href: "/", active?: @current_page == :home}) %>
              <%= nav_link(%{text: "Features", href: "/features", active?: @current_page == :features}) %>
              <%= nav_link(%{text: "Pricing", href: "/pricing", active?: @current_page == :pricing}) %>
              <%= nav_link(%{text: "Documentation", href: "/documentation", active?: @current_page == :documentation}) %>
            </div>
          </div>
          <div class="hidden sm:ml-6 sm:flex sm:items-center">
            <%= if @current_user do %>
              <div class="flex items-center space-x-4 mr-4">
                <%= nav_link(%{text: "Entries", href: "/app/entries", active?: @current_page == :entries}) %>
                <%= nav_link(%{text: "Tags", href: "/app/tags", active?: @current_page == :tags}) %>
                <%= nav_link(%{text: "API Keys", href: "/app/api-keys", active?: @current_page == :api_keys}) %>
              </div>
              <div class="ml-3 relative">
                <button type="button" data-test-id="user-menu-button" class="bg-white rounded-full flex text-sm focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500">
                  <span class="sr-only">Open user menu</span>
                  <span class="h-8 w-8 rounded-full bg-indigo-100 flex items-center justify-center">
                    <%= String.first(@current_user.email) %>
                  </span>
                </button>
              </div>
            <% else %>
              <div class="flex items-center space-x-4">
                <a href="/login" data-test-id="nav-login" class="text-gray-500 hover:text-gray-700 px-3 py-2 rounded-md text-sm font-medium">
                  Sign In
                </a>
                <a href="/register" data-test-id="nav-register" class="bg-indigo-600 text-white hover:bg-indigo-700 px-3 py-2 rounded-md text-sm font-medium">
                  Sign up
                </a>
              </div>
            <% end %>
          </div>
          <div class="-mr-2 flex items-center sm:hidden">
            <button type="button" data-test-id="mobile-menu-button" class="inline-flex items-center justify-center p-2 rounded-md text-gray-400 hover:text-gray-500 hover:bg-gray-100 focus:outline-none focus:ring-2 focus:ring-inset focus:ring-indigo-500">
              <span class="sr-only">Open main menu</span>
              <svg class="block h-6 w-6" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h16"></path>
              </svg>
            </button>
          </div>
        </div>
      </div>

      <div class="sm:hidden" data-test-id="mobile-nav">
        <div class="pt-2 pb-3 space-y-1">
          <%= mobile_nav_link(%{text: "Home", href: "/", active?: @current_page == :home}) %>
          <%= mobile_nav_link(%{text: "Features", href: "/features", active?: @current_page == :features}) %>
          <%= mobile_nav_link(%{text: "Pricing", href: "/pricing", active?: @current_page == :pricing}) %>
          <%= mobile_nav_link(%{text: "Documentation", href: "/documentation", active?: @current_page == :documentation}) %>
        </div>
        <%= if @current_user do %>
          <div class="pt-4 pb-3 border-t border-gray-200">
            <div class="space-y-1">
              <%= mobile_nav_link(%{text: "Entries", href: "/app/entries", active?: @current_page == :entries}) %>
              <%= mobile_nav_link(%{text: "Tags", href: "/app/tags", active?: @current_page == :tags}) %>
              <%= mobile_nav_link(%{text: "API Keys", href: "/app/api-keys", active?: @current_page == :api_keys}) %>
            </div>
            <div class="mt-3 flex items-center px-4">
              <div class="flex-shrink-0">
                <span class="h-10 w-10 rounded-full bg-indigo-100 flex items-center justify-center">
                  <%= String.first(@current_user.email) %>
                </span>
              </div>
              <div class="ml-3">
                <div class="text-base font-medium text-gray-800"><%= @current_user.email %></div>
              </div>
            </div>
          </div>
        <% else %>
          <div class="pt-4 pb-3 border-t border-gray-200">
            <div class="space-y-1">
              <a href="/login" class="block pl-3 pr-4 py-2 border-l-4 border-transparent text-base font-medium text-gray-500 hover:bg-gray-50 hover:border-gray-300 hover:text-gray-700">
                Sign in
              </a>
              <a href="/register" class="block pl-3 pr-4 py-2 border-l-4 border-transparent text-base font-medium text-gray-500 hover:bg-gray-50 hover:border-gray-300 hover:text-gray-700">
                Sign up
              </a>
            </div>
          </div>
        <% end %>
      </div>
    </nav>
    """
  end

  defp nav_link(assigns) do
    ~H"""
    <a
      href={@href}
      data-test-id={"nav-#{String.downcase(@text)}"}
      class={"inline-flex items-center px-1 pt-1 border-b-2 text-sm font-medium #{if @active?, do: "border-indigo-500 text-gray-900", else: "border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700"}"}
      aria-current={if @active?, do: "page"}
    >
      <%= @text %>
    </a>
    """
  end

  defp mobile_nav_link(assigns) do
    ~H"""
    <a
      href={@href}
      data-test-id={"mobile-nav-#{String.downcase(@text)}"}
      class={"block pl-3 pr-4 py-2 border-l-4 text-base font-medium #{if @active?, do: "bg-indigo-50 border-indigo-500 text-indigo-700", else: "border-transparent text-gray-500 hover:bg-gray-50 hover:border-gray-300 hover:text-gray-700"}"}
    >
      <%= @text %>
    </a>
    """
  end
end