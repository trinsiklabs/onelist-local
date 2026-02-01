defmodule OnelistWeb.UserSessionHTML do
  use OnelistWeb, :html
  
  alias Onelist.Security
  
  @doc """
  Renders the user sessions index page.
  """
  def index(assigns) do
    ~H"""
    <div class="sessions-container">
      <h1>Manage Your Sessions</h1>
      
      <p class="sessions-info">
        You are currently signed in on <%= length(@sessions) %> <%= if length(@sessions) == 1, do: "device", else: "devices" %>.
        Sessions will automatically expire after 30 days of inactivity.
      </p>
      
      <div class="actions">
        <.link 
          href={~p"/app/sessions/all"} 
          method="delete" 
          data-confirm="Are you sure you want to sign out from all other devices?" 
          class="btn btn-secondary"
        >
          Sign out from all other devices
        </.link>
      </div>
      
      <%= for {device_type, sessions} <- @grouped_sessions do %>
        <section class="device-group">
          <h2><%= device_type %></h2>
          
          <div class="sessions-list">
            <%= for session <- sessions do %>
              <div class={["session-card", session.id == @current_session_id && "current"]} data-session-id={session.id}>
                <div class="session-info">
                  <div class="device">
                    <span><%= device_icon(session.device_name) %> <%= session.device_name %></span>
                    <%= if session.id == @current_session_id do %>
                      <span class="current-badge">Current Session</span>
                    <% end %>
                  </div>
                  
                  <div class="details">
                    <div class="location">
                      <span class="label">Location:</span>
                      <span>Unknown</span>
                    </div>
                    
                    <div class="last-active">
                      <span class="label">Last active:</span>
                      <span><%= format_datetime(session.last_active_at) %></span>
                    </div>
                    
                    <div class="browser">
                      <span class="label">Browser:</span>
                      <span><%= Security.extract_browser(session.user_agent) %></span>
                    </div>
                  </div>
                </div>
                
                <div class="actions">
                  <%= if session.id != @current_session_id do %>
                    <.link 
                      href={~p"/app/sessions/#{session.id}"} 
                      method="delete" 
                      data-confirm="Are you sure you want to sign out this session?" 
                      class="btn btn-danger"
                    >
                      Sign Out
                    </.link>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        </section>
      <% end %>
    </div>
    """
  end
  
  # Helper function to get an icon for a device type
  defp device_icon(device_name) do
    cond do
      String.contains?(device_name, "iPhone") -> "📱"
      String.contains?(device_name, "iPad") -> "📱"
      String.contains?(device_name, "Android") -> "📱"
      String.contains?(device_name, "Windows") -> "💻"
      String.contains?(device_name, "Mac") -> "💻"
      String.contains?(device_name, "Linux") -> "💻"
      true -> "🖥️"
    end
  end
  
  # Helper function to format datetime
  defp format_datetime(datetime) do
    # Format as "Jan 1, 2023 at 12:34 PM"
    Calendar.strftime(datetime, "%b %d, %Y at %I:%M %p")
  end
end 