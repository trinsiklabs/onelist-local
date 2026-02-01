defmodule OnelistWeb.Auth.AuthLayoutComponent do
  use OnelistWeb, :live_component

  def update(assigns, socket) do
    socket = 
      socket
      |> assign(assigns)
      |> validate_assigns()
  
    {:ok, socket}
  end
  
  defp validate_assigns(socket) do
    assigns = socket.assigns
    
    if !Map.has_key?(assigns, :page_title) do
      raise ArgumentError, "page_title is required for AuthLayoutComponent"
    end
    
    socket
  end

  def render(assigns) do
    ~H"""
    <div data-test-id="auth-layout-container" class="min-h-screen bg-gray-50 flex flex-col justify-center py-12 sm:px-6 lg:px-8">
      <div data-test-id="auth-layout-header" class="sm:mx-auto sm:w-full sm:max-w-md">
        <div class="text-center">
          <a href="/" class="text-indigo-600 text-3xl font-bold">
            Onelist
          </a>
        </div>
        <h2 class="mt-6 text-center text-3xl font-extrabold text-gray-900" role="heading" aria-level="1">
          <%= @page_title %>
        </h2>
        <%= if Map.get(assigns, :page_description) do %>
          <p class="mt-2 text-center text-sm text-gray-600" aria-description="true">
            <%= @page_description %>
          </p>
        <% end %>
      </div>

      <div data-test-id="auth-layout-content" class="mt-8 sm:mx-auto sm:w-full sm:max-w-md">
        <div class="bg-white py-8 px-4 shadow sm:rounded-lg sm:px-10">
          <%= if Map.has_key?(assigns, :inner_block) do %>
            <%= render_slot(@inner_block) %>
          <% else %>
            <div class="text-center text-gray-500">Content goes here</div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end 