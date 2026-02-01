defmodule OnelistWeb.Entries.EntryListLive do
  use OnelistWeb, :live_view

  alias Onelist.Entries

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns[:current_user] do
      entries = Entries.list_user_entries(socket.assigns.current_user)

      {:ok, assign(socket,
        page_title: "Entries",
        entries: entries,
        filter: nil
      )}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    filter = params["type"]
    entries = load_entries(socket.assigns.current_user, filter)

    {:noreply, assign(socket, entries: entries, filter: filter)}
  end

  @impl true
  def handle_event("filter", %{"type" => type}, socket) do
    {:noreply, push_patch(socket, to: ~p"/app/entries?type=#{type}")}
  end

  @impl true
  def handle_event("clear_filter", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/app/entries")}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    entry = Entries.get_user_entry(socket.assigns.current_user, id)

    if entry do
      {:ok, _} = Entries.delete_entry(entry)
      entries = load_entries(socket.assigns.current_user, socket.assigns.filter)
      {:noreply, assign(socket, entries: entries)}
    else
      {:noreply, socket}
    end
  end

  defp load_entries(user, nil), do: Entries.list_user_entries(user)
  defp load_entries(user, type), do: Entries.list_user_entries(user, entry_type: type)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8">
      <div class="flex justify-between items-center mb-6">
        <h1 class="text-2xl font-bold text-gray-900">Entries</h1>
        <.link
          navigate={~p"/app/entries/new"}
          class="bg-indigo-600 text-white px-4 py-2 rounded-md hover:bg-indigo-700"
          data-test-id="new-entry-button"
        >
          New Entry
        </.link>
      </div>

      <div class="mb-6 flex gap-2">
        <button
          phx-click="clear_filter"
          class={"px-3 py-1 rounded-md text-sm #{if @filter == nil, do: "bg-indigo-600 text-white", else: "bg-gray-200 text-gray-700"}"}
          data-test-id="filter-all"
        >
          All
        </button>
        <%= for type <- ~w(note memory photo video) do %>
          <button
            phx-click="filter"
            phx-value-type={type}
            class={"px-3 py-1 rounded-md text-sm capitalize #{if @filter == type, do: "bg-indigo-600 text-white", else: "bg-gray-200 text-gray-700"}"}
            data-test-id={"filter-#{type}"}
          >
            <%= type %>
          </button>
        <% end %>
      </div>

      <%= if Enum.empty?(@entries) do %>
        <div class="text-center py-12 text-gray-500">
          <p class="text-lg">No entries yet</p>
          <p class="text-sm mt-2">Create your first entry to get started.</p>
        </div>
      <% else %>
        <div class="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
          <%= for entry <- @entries do %>
            <div class="bg-white rounded-lg shadow p-4 hover:shadow-md transition-shadow">
              <div class="flex justify-between items-start">
                <.link navigate={~p"/app/entries/#{entry.id}/edit"} class="flex-1">
                  <h3 class="font-medium text-gray-900">
                    <%= entry.title || "Untitled" %>
                  </h3>
                  <p class="text-sm text-gray-500 mt-1 capitalize">
                    <%= entry.entry_type %>
                  </p>
                  <p class="text-xs text-gray-400 mt-2">
                    <%= Calendar.strftime(entry.inserted_at, "%b %d, %Y") %>
                  </p>
                </.link>
                <button
                  phx-click="delete"
                  phx-value-id={entry.id}
                  class="text-red-500 hover:text-red-700 ml-2"
                  data-test-id={"delete-entry-#{entry.id}"}
                  data-confirm="Are you sure you want to delete this entry?"
                >
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                    <path fill-rule="evenodd" d="M9 2a1 1 0 00-.894.553L7.382 4H4a1 1 0 000 2v10a2 2 0 002 2h8a2 2 0 002-2V6a1 1 0 100-2h-3.382l-.724-1.447A1 1 0 0011 2H9zM7 8a1 1 0 012 0v6a1 1 0 11-2 0V8zm5-1a1 1 0 00-1 1v6a1 1 0 102 0V8a1 1 0 00-1-1z" clip-rule="evenodd" />
                  </svg>
                </button>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
