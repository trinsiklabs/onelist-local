defmodule OnelistWeb.Account.UsernameSetupLive do
  @moduledoc """
  LiveView for setting up a user's username.
  Required before users can publish public entries.
  """
  use OnelistWeb, :live_view

  alias Onelist.Accounts

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    changeset = Accounts.User.username_changeset(user, %{})

    {:ok,
     assign(socket,
       page_title: "Set Username",
       changeset: changeset,
       username: "",
       availability: nil,
       checking: false
     )}
  end

  @impl true
  def handle_event("validate", %{"username" => username}, socket) do
    user = socket.assigns.current_user

    changeset =
      user
      |> Accounts.User.username_changeset(%{username: username})
      |> Map.put(:action, :validate)

    # Check availability if username is valid format
    availability = check_availability(username, changeset)

    {:noreply,
     assign(socket,
       changeset: changeset,
       username: username,
       availability: availability
     )}
  end

  @impl true
  def handle_event("save", %{"username" => username}, socket) do
    user = socket.assigns.current_user

    case Accounts.set_username(user, username) do
      {:ok, _updated_user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Username set successfully!")
         |> push_navigate(to: ~p"/app/entries")}

      {:error, changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  defp check_availability(username, changeset) do
    # Only check if there are no validation errors for username format
    username_errors = Keyword.get_values(changeset.errors, :username)

    cond do
      String.length(username) < 3 ->
        nil

      Enum.any?(username_errors) ->
        nil

      Accounts.username_available?(username) ->
        :available

      true ->
        :taken
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 flex flex-col justify-center py-12 sm:px-6 lg:px-8">
      <div class="sm:mx-auto sm:w-full sm:max-w-md">
        <h2 class="mt-6 text-center text-3xl font-bold tracking-tight text-gray-900">
          Choose your username
        </h2>
        <p class="mt-2 text-center text-sm text-gray-600">
          Your username will be used in public URLs for your shared entries.
        </p>
      </div>

      <div class="mt-8 sm:mx-auto sm:w-full sm:max-w-md">
        <div class="bg-white py-8 px-4 shadow sm:rounded-lg sm:px-10">
          <.form
            for={@changeset}
            id="username-form"
            phx-change="validate"
            phx-submit="save"
            class="space-y-6"
          >
            <div>
              <label for="username" class="block text-sm font-medium text-gray-700">
                Username
              </label>
              <div class="mt-1 relative">
                <input
                  type="text"
                  name="username"
                  id="username"
                  data-testid="username-input"
                  value={@username}
                  class={[
                    "block w-full rounded-md shadow-sm sm:text-sm",
                    "focus:ring-indigo-500 focus:border-indigo-500",
                    username_input_class(@availability, @changeset)
                  ]}
                  placeholder="yourname"
                  autocomplete="username"
                  phx-debounce="300"
                />
                <div class="absolute inset-y-0 right-0 flex items-center pr-3">
                  <%= if @availability == :available do %>
                    <span data-testid="username-available" class="text-green-500">
                      <svg class="h-5 w-5" fill="currentColor" viewBox="0 0 20 20">
                        <path
                          fill-rule="evenodd"
                          d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                          clip-rule="evenodd"
                        />
                      </svg>
                    </span>
                  <% end %>
                  <%= if @availability == :taken do %>
                    <span data-testid="username-taken" class="text-red-500">
                      <svg class="h-5 w-5" fill="currentColor" viewBox="0 0 20 20">
                        <path
                          fill-rule="evenodd"
                          d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z"
                          clip-rule="evenodd"
                        />
                      </svg>
                    </span>
                  <% end %>
                </div>
              </div>

              <%= if @availability == :available do %>
                <p class="mt-2 text-sm text-green-600" data-testid="username-available">
                  Username is available!
                </p>
              <% end %>

              <%= if @availability == :taken do %>
                <p class="mt-2 text-sm text-red-600" data-testid="username-taken">
                  This username is already taken or reserved.
                </p>
              <% end %>

              <%= for error <- username_errors(@changeset) do %>
                <p class="mt-2 text-sm text-red-600" data-testid="username-error"><%= error %></p>
              <% end %>

              <p class="mt-2 text-xs text-gray-500">
                3-30 characters. Letters, numbers, underscores, and hyphens only.
                Must start and end with a letter or number.
              </p>
            </div>

            <div>
              <p class="text-sm text-gray-600 mb-4">
                Your public entries will be available at: <br />
                <code class="text-indigo-600 bg-indigo-50 px-2 py-1 rounded text-sm">
                  onelist.my/<%= if @username != "", do: @username, else: "yourname" %>/entry-id
                </code>
              </p>
            </div>

            <div>
              <button
                type="submit"
                disabled={@availability != :available}
                class={[
                  "w-full flex justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white",
                  if(@availability == :available,
                    do:
                      "bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500",
                    else: "bg-gray-400 cursor-not-allowed"
                  )
                ]}
              >
                Set Username
              </button>
            </div>
          </.form>

          <div class="mt-6">
            <.link navigate={~p"/app/entries"} class="text-sm text-gray-600 hover:text-gray-900">
              &larr; Back to entries
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp username_input_class(:available, _changeset), do: "border-green-300"
  defp username_input_class(:taken, _changeset), do: "border-red-300"

  defp username_input_class(nil, changeset) do
    if Keyword.has_key?(changeset.errors, :username) do
      "border-red-300"
    else
      "border-gray-300"
    end
  end

  defp username_errors(changeset) do
    changeset.errors
    |> Keyword.get_values(:username)
    |> Enum.map(fn {msg, _opts} -> msg end)
  end
end
