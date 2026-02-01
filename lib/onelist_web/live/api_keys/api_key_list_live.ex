defmodule OnelistWeb.ApiKeys.ApiKeyListLive do
  use OnelistWeb, :live_view

  alias Onelist.ApiKeys
  alias Onelist.ApiKeys.ApiKey

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns[:current_user] do
      api_keys = ApiKeys.list_user_api_keys(socket.assigns.current_user)

      {:ok, assign(socket,
        page_title: "API Keys",
        api_keys: api_keys,
        new_key_changeset: ApiKey.changeset(%ApiKey{}, %{}),
        newly_created_key: nil
      )}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_event("create_key", %{"api_key" => key_params}, socket) do
    case ApiKeys.create_api_key(socket.assigns.current_user, key_params) do
      {:ok, %{api_key: _api_key, raw_key: raw_key}} ->
        api_keys = ApiKeys.list_user_api_keys(socket.assigns.current_user)
        {:noreply, assign(socket,
          api_keys: api_keys,
          new_key_changeset: ApiKey.changeset(%ApiKey{}, %{}),
          newly_created_key: raw_key
        )}

      {:error, changeset} ->
        {:noreply, assign(socket, new_key_changeset: changeset)}
    end
  end

  @impl true
  def handle_event("dismiss_new_key", _params, socket) do
    {:noreply, assign(socket, newly_created_key: nil)}
  end

  @impl true
  def handle_event("revoke_key", %{"id" => id}, socket) do
    api_key = ApiKeys.get_api_key(id)

    if api_key && api_key.user_id == socket.assigns.current_user.id do
      {:ok, _} = ApiKeys.revoke_api_key(api_key)
      api_keys = ApiKeys.list_user_api_keys(socket.assigns.current_user)
      {:noreply, assign(socket, api_keys: api_keys)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("copy_key", _params, socket) do
    # Copying is handled client-side via JavaScript
    {:noreply, put_flash(socket, :info, "Key copied to clipboard")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8 max-w-2xl">
      <h1 class="text-2xl font-bold text-gray-900 mb-6">API Keys</h1>

      <div class="bg-white rounded-lg shadow mb-6 p-4">
        <h2 class="text-lg font-medium text-gray-900 mb-4">Generate New Key</h2>
        <.form
          for={@new_key_changeset}
          id="new-api-key-form"
          phx-submit="create_key"
          class="flex gap-2"
        >
          <input
            type="text"
            name="api_key[name]"
            placeholder="Key name (e.g., Production API)"
            class="flex-1 rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
            required
          />
          <button
            type="submit"
            class="bg-indigo-600 text-white px-4 py-2 rounded-md hover:bg-indigo-700"
          >
            Generate
          </button>
        </.form>
      </div>

      <%= if @newly_created_key do %>
        <div class="bg-green-50 border border-green-200 rounded-lg p-4 mb-6">
          <div class="flex items-start">
            <div class="flex-1">
              <h3 class="text-green-800 font-medium">New API Key Created</h3>
              <p class="text-green-700 text-sm mt-1">
                Make sure to copy your API key now. You won't be able to see it again!
              </p>
              <div class="mt-3 flex items-center gap-2">
                <code class="bg-green-100 px-3 py-2 rounded text-sm font-mono flex-1 break-all">
                  <%= @newly_created_key %>
                </code>
                <button
                  phx-click={JS.dispatch("phx:copy", to: "#new-key-display")}
                  class="text-green-700 hover:text-green-900"
                  title="Copy to clipboard"
                >
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                    <path d="M8 3a1 1 0 011-1h2a1 1 0 110 2H9a1 1 0 01-1-1z" />
                    <path d="M6 3a2 2 0 00-2 2v11a2 2 0 002 2h8a2 2 0 002-2V5a2 2 0 00-2-2 3 3 0 01-3 3H9a3 3 0 01-3-3z" />
                  </svg>
                </button>
              </div>
              <input type="hidden" id="new-key-display" value={@newly_created_key} />
            </div>
            <button
              phx-click="dismiss_new_key"
              class="text-green-700 hover:text-green-900"
            >
              <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd" />
              </svg>
            </button>
          </div>
        </div>
      <% end %>

      <%= if Enum.empty?(@api_keys) do %>
        <div class="text-center py-12 text-gray-500">
          <p class="text-lg">No API keys yet</p>
          <p class="text-sm mt-2">Generate an API key to access the Onelist API programmatically.</p>
        </div>
      <% else %>
        <div class="bg-white rounded-lg shadow divide-y">
          <%= for api_key <- @api_keys do %>
            <div class="p-4">
              <div class="flex items-center justify-between">
                <div>
                  <span class="font-medium text-gray-900"><%= api_key.name %></span>
                  <div class="text-sm text-gray-500 mt-1">
                    <code class="bg-gray-100 px-2 py-1 rounded">ol_<%= api_key.prefix %>...</code>
                  </div>
                </div>
                <button
                  phx-click="revoke_key"
                  phx-value-id={api_key.id}
                  class="text-red-500 hover:text-red-700"
                  data-test-id={"revoke-key-#{api_key.id}"}
                  data-confirm="Are you sure you want to revoke this API key? This action cannot be undone."
                >
                  Revoke
                </button>
              </div>
              <div class="text-xs text-gray-400 mt-2">
                Created <%= Calendar.strftime(api_key.inserted_at, "%b %d, %Y") %>
                <%= if api_key.last_used_at do %>
                  <span class="ml-2">
                    Last used <%= Calendar.strftime(api_key.last_used_at, "%b %d, %Y at %H:%M") %>
                  </span>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>

      <div class="mt-8 p-4 bg-gray-50 rounded-lg">
        <h3 class="font-medium text-gray-900 mb-2">API Usage</h3>
        <p class="text-sm text-gray-600 mb-4">
          Include your API key in the Authorization header when making requests:
        </p>
        <pre class="bg-gray-800 text-gray-100 p-3 rounded text-sm overflow-x-auto">Authorization: Bearer ol_your_api_key_here</pre>
      </div>
    </div>
    """
  end
end
