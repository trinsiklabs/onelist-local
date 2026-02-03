defmodule OnelistWeb.Entries.Components.PublicToggleComponent do
  @moduledoc """
  LiveComponent for toggling entry public/private status.
  Shows a confirmation dialog when making an entry public.
  """
  use OnelistWeb, :live_component

  alias Onelist.Entries

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       show_dialog: false,
       assets: [],
       public_url_preview: nil
     )}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def handle_event("toggle_public", _params, socket) do
    entry = socket.assigns.entry

    if entry.public do
      # Making private - no confirmation needed
      make_private(socket)
    else
      # Making public - show confirmation dialog
      show_publish_dialog(socket)
    end
  end

  @impl true
  def handle_event("confirm_publish", _params, socket) do
    entry = socket.assigns.entry
    user = socket.assigns.user

    # Check if user has username
    if user.username do
      case Entries.make_entry_public(entry) do
        {:ok, updated_entry} ->
          send(self(), {:entry_updated, updated_entry})

          {:noreply,
           assign(socket,
             entry: updated_entry,
             show_dialog: false
           )}

        {:error, _reason} ->
          {:noreply,
           socket
           |> assign(show_dialog: false)
           |> send_flash_to_parent(:error, "Failed to publish entry")}
      end
    else
      # Redirect to username setup
      {:noreply, push_navigate(socket, to: ~p"/app/account/username")}
    end
  end

  @impl true
  def handle_event("cancel_publish", _params, socket) do
    {:noreply, assign(socket, show_dialog: false)}
  end

  @impl true
  def handle_event("copy_url", _params, socket) do
    # URL copying is handled client-side via JS hook
    {:noreply, socket}
  end

  defp show_publish_dialog(socket) do
    entry = socket.assigns.entry

    # Get publish preview info
    {:ok, preview} = Entries.get_publish_preview(entry)

    {:noreply,
     assign(socket,
       show_dialog: true,
       assets: preview.assets,
       public_url_preview: preview.public_url_preview
     )}
  end

  defp make_private(socket) do
    entry = socket.assigns.entry

    case Entries.make_entry_private(entry) do
      {:ok, updated_entry} ->
        send(self(), {:entry_updated, updated_entry})
        {:noreply, assign(socket, entry: updated_entry)}

      {:error, _reason} ->
        {:noreply, send_flash_to_parent(socket, :error, "Failed to make entry private")}
    end
  end

  defp send_flash_to_parent(socket, kind, message) do
    # Send flash to parent LiveView
    send(self(), {:flash, kind, message})
    socket
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="public-toggle-component">
      <!-- Toggle Button -->
      <button
        type="button"
        phx-click="toggle_public"
        phx-target={@myself}
        data-testid="public-toggle"
        class={[
          "relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2",
          if(@entry.public, do: "bg-indigo-600", else: "bg-gray-200")
        ]}
      >
        <span
          data-testid={if(@entry.public, do: "toggle-public", else: "toggle-private")}
          class={[
            "pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out",
            if(@entry.public, do: "translate-x-5", else: "translate-x-0")
          ]}
        />
      </button>

      <span class="ml-3 text-sm">
        <%= if @entry.public do %>
          <span class="text-green-600 font-medium">Public</span>
          <span class="text-gray-500">- Anyone with the link can view</span>
        <% else %>
          <span class="text-gray-600">Private</span>
          <span class="text-gray-500">- Only you can view</span>
        <% end %>
      </span>
      <!-- Copy URL button for public entries -->
      <%= if @entry.public do %>
        <button
          type="button"
          phx-click="copy_url"
          phx-target={@myself}
          data-testid="copy-url"
          data-action="copy-url"
          data-url={Entries.public_entry_url(@entry)}
          phx-hook="CopyToClipboard"
          id={"copy-url-#{@entry.id}"}
          class="ml-4 inline-flex items-center px-3 py-1 border border-gray-300 shadow-sm text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
        >
          <svg class="h-4 w-4 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M8 5H6a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2v-1M8 5a2 2 0 002 2h2a2 2 0 002-2M8 5a2 2 0 012-2h2a2 2 0 012 2m0 0h2a2 2 0 012 2v3m2 4H10m0 0l3-3m-3 3l3 3"
            />
          </svg>
          Copy URL
        </button>
      <% end %>
      <!-- Publish Confirmation Dialog -->
      <%= if @show_dialog do %>
        <div
          class="fixed inset-0 z-50 overflow-y-auto"
          aria-labelledby="publish-dialog-title"
          role="dialog"
          aria-modal="true"
          data-testid="publish-dialog"
        >
          <div class="flex min-h-screen items-end justify-center px-4 pt-4 pb-20 text-center sm:block sm:p-0">
            <!-- Background overlay -->
            <div
              class="fixed inset-0 bg-gray-500 bg-opacity-75 transition-opacity"
              phx-click="cancel_publish"
              phx-target={@myself}
            >
            </div>
            <!-- Dialog panel -->
            <div class="relative inline-block transform overflow-hidden rounded-lg bg-white text-left align-bottom shadow-xl transition-all sm:my-8 sm:w-full sm:max-w-lg sm:align-middle">
              <div class="bg-white px-4 pt-5 pb-4 sm:p-6 sm:pb-4">
                <div class="sm:flex sm:items-start">
                  <div class="mx-auto flex h-12 w-12 flex-shrink-0 items-center justify-center rounded-full bg-indigo-100 sm:mx-0 sm:h-10 sm:w-10">
                    <svg
                      class="h-6 w-6 text-indigo-600"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M3.055 11H5a2 2 0 012 2v1a2 2 0 002 2 2 2 0 012 2v2.945M8 3.935V5.5A2.5 2.5 0 0010.5 8h.5a2 2 0 012 2 2 2 0 104 0 2 2 0 012-2h1.064M15 20.488V18a2 2 0 012-2h3.064M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                      />
                    </svg>
                  </div>
                  <div class="mt-3 text-center sm:mt-0 sm:ml-4 sm:text-left">
                    <h3 class="text-lg font-medium leading-6 text-gray-900" id="publish-dialog-title">
                      MAKE ENTRY PUBLIC
                    </h3>
                    <div class="mt-2">
                      <p class="text-sm text-gray-500">
                        This entry will be publicly accessible at:
                      </p>
                      <p class="mt-2 text-sm font-mono bg-gray-100 p-2 rounded break-all">
                        <%= @public_url_preview %>
                      </p>

                      <%= if Enum.any?(@assets) do %>
                        <div class="mt-4">
                          <p class="text-sm text-gray-500 mb-2">
                            The following assets will be
                            <span class="font-semibold text-amber-600">DECRYPTED</span>
                            and made publicly accessible:
                          </p>
                          <ul class="text-sm space-y-1 bg-amber-50 p-3 rounded-md">
                            <%= for asset <- @assets do %>
                              <li class="flex justify-between items-center">
                                <span class="text-gray-700"><%= asset.filename %></span>
                                <span class="text-gray-500 text-xs">
                                  <%= format_file_size(asset.size) %>
                                </span>
                              </li>
                            <% end %>
                          </ul>
                        </div>
                      <% end %>
                    </div>
                  </div>
                </div>
              </div>
              <div class="bg-gray-50 px-4 py-3 sm:flex sm:flex-row-reverse sm:px-6">
                <button
                  type="button"
                  phx-click="confirm_publish"
                  phx-target={@myself}
                  data-testid="confirm-publish"
                  class="inline-flex w-full justify-center rounded-md border border-transparent bg-indigo-600 px-4 py-2 text-base font-medium text-white shadow-sm hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 sm:ml-3 sm:w-auto sm:text-sm"
                >
                  Make Public
                </button>
                <button
                  type="button"
                  phx-click="cancel_publish"
                  phx-target={@myself}
                  data-testid="cancel-publish"
                  class="mt-3 inline-flex w-full justify-center rounded-md border border-gray-300 bg-white px-4 py-2 text-base font-medium text-gray-700 shadow-sm hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 sm:mt-0 sm:ml-3 sm:w-auto sm:text-sm"
                >
                  Cancel
                </button>
              </div>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp format_file_size(nil), do: "0 B"
  defp format_file_size(bytes) when bytes < 1024, do: "#{bytes} B"

  defp format_file_size(bytes) when bytes < 1024 * 1024 do
    kb = Float.round(bytes / 1024, 1)
    "#{kb} KB"
  end

  defp format_file_size(bytes) do
    mb = Float.round(bytes / (1024 * 1024), 1)
    "#{mb} MB"
  end
end
