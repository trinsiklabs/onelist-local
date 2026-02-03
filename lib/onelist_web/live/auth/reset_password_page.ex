defmodule OnelistWeb.Auth.ResetPasswordPage do
  use OnelistWeb, :live_view
  alias Onelist.Accounts

  @impl true
  def mount(_params, _session, socket) do
    # Store connection info in process dictionary for tracking
    if connected?(socket) do
      ip_address = get_client_ip(socket)
      user_agent = get_user_agent(socket)

      Process.put(:current_ip_address, ip_address)
      Process.put(:current_user_agent, user_agent)
    end

    {:ok,
     assign(socket,
       page_title: "Reset Password",
       error_message: nil,
       loading: false,
       success: false,
       token: nil,
       form: to_form(%{"password" => "", "password_confirmation" => ""}, as: :reset_password)
     )}
  end

  @impl true
  def handle_params(%{"token" => token}, _uri, socket) do
    # Check if rate limited
    ip_address = Process.get(:current_ip_address, "unknown")

    case Accounts.rate_limited?("reset_page", ip_address) do
      {:ok, false} ->
        # Not rate limited - attempt token validation
        case Accounts.get_user_by_reset_token(token) do
          {:ok, user} ->
            # Valid token, setup form
            changeset = Accounts.change_user_password(user)
            form = to_form(changeset, as: :reset_password)

            {:noreply,
             assign(socket,
               token: token,
               user: user,
               form: form
             )}

          {:error, :expired_token} ->
            # Track the attempt
            track_token_validation(token, "expired_token")

            # Redirect with an error message
            socket =
              socket
              |> put_flash(
                :error,
                "The password reset link has expired. Please request a new one."
              )
              |> push_navigate(to: ~p"/forgot-password")

            {:noreply, socket}

          {:error, _} ->
            # Track the attempt
            track_token_validation(token, "invalid_token")

            # Redirect with generic error to prevent enumeration
            socket =
              socket
              |> put_flash(
                :error,
                "The password reset link is invalid. Please request a new one."
              )
              |> push_navigate(to: ~p"/forgot-password")

            {:noreply, socket}
        end

      {:error, :rate_limited, timeout} ->
        # Track the rate limited attempt
        track_token_validation(token, "rate_limited")

        # Redirect with rate limiting message
        socket =
          socket
          |> put_flash(
            :error,
            "Too many attempts. Please try again in #{div(timeout, 60)} minutes."
          )
          |> push_navigate(to: ~p"/forgot-password?rate_limited=true")

        {:noreply, socket}
    end
  end

  # Handle missing token parameter
  def handle_params(_params, _uri, socket) do
    socket =
      socket
      |> put_flash(:error, "Invalid password reset link")
      |> push_navigate(to: ~p"/forgot-password")

    {:noreply, socket}
  end

  @impl true
  def handle_event("validate", %{"reset_password" => params}, socket) do
    %{user: user} = socket.assigns

    changeset =
      user
      |> Accounts.change_user_password(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: :reset_password))}
  end

  @impl true
  def handle_event("submit", %{"reset_password" => params}, socket) do
    %{"password" => password} = params
    %{token: token, user: user} = socket.assigns

    changeset =
      user
      |> Accounts.change_user_password(params)

    if changeset.valid? do
      # Set loading state
      socket = assign(socket, loading: true)

      # Process the reset in an async task
      Task.start(fn -> process_reset(token, password, user, self()) end)

      {:noreply, socket}
    else
      changeset = Map.put(changeset, :action, :update)
      {:noreply, assign(socket, form: to_form(changeset, as: :reset_password))}
    end
  end

  @impl true
  def handle_info({:reset_complete, :success}, socket) do
    # On successful reset, set success state and show message
    # This will allow us to show a success message on the page before redirecting
    Process.send_after(self(), :redirect_to_login, 2000)

    {:noreply,
     assign(socket,
       loading: false,
       success: true,
       error_message: nil
     )}
  end

  @impl true
  def handle_info({:reset_complete, :error, message}, socket) do
    # On error, show message
    {:noreply,
     assign(socket,
       loading: false,
       success: false,
       error_message: message
     )}
  end

  @impl true
  def handle_info(:redirect_to_login, socket) do
    # Redirect to login page after successful reset
    socket =
      socket
      |> put_flash(:info, "Password reset successfully. Please sign in with your new password.")
      |> push_navigate(to: ~p"/login?reset=success")

    {:noreply, socket}
  end

  # Process the reset in a separate task
  defp process_reset(token, password, user, pid) do
    case Accounts.reset_password(user, token, %{password: password}) do
      {:ok, _user} ->
        # Track successful reset
        track_password_reset(user, true)
        send(pid, {:reset_complete, :success})

      {:error, %Ecto.Changeset{} = _changeset} ->
        # Password validation failed
        track_password_reset(user, false, "validation_error")
        send(pid, {:reset_complete, :error, "Password does not meet requirements"})

      {:error, :invalid_token} ->
        # Token became invalid during process (e.g., used twice)
        track_password_reset(user, false, "invalid_token")

        send(
          pid,
          {:reset_complete, :error, "Reset link is no longer valid. Please request a new one."}
        )

      {:error, :expired_token} ->
        # Token expired during process
        track_password_reset(user, false, "expired_token")
        send(pid, {:reset_complete, :error, "Reset link has expired. Please request a new one."})

      {:error, _} ->
        # Generic error
        track_password_reset(user, false, "unknown_error")

        send(
          pid,
          {:reset_complete, :error,
           "An error occurred. Please try again or request a new reset link."}
        )
    end
  end

  # Track token validation attempts
  defp track_token_validation(_token, reason) do
    ip_address = Process.get(:current_ip_address, "unknown")
    user_agent = Process.get(:current_user_agent, "unknown")

    Accounts.track_login_attempt(
      "token_validation",
      nil,
      ip_address,
      user_agent,
      false,
      "reset_token_validation_#{reason}"
    )
  end

  # Track password reset attempts
  defp track_password_reset(user, success, reason \\ nil) do
    ip_address = Process.get(:current_ip_address, "unknown")
    user_agent = Process.get(:current_user_agent, "unknown")

    Accounts.track_login_attempt(
      user.email,
      user,
      ip_address,
      user_agent,
      success,
      reason
    )
  end

  # Extract client IP from socket
  defp get_client_ip(socket) do
    case socket.assigns[:client_ip] do
      nil -> "unknown"
      ip -> ip
    end
  end

  # Extract user agent from socket
  defp get_user_agent(socket) do
    case socket.assigns[:user_agent] do
      nil -> "unknown"
      ua -> ua
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 flex flex-col justify-center py-12 sm:px-6 lg:px-8">
      <div class="sm:mx-auto sm:w-full sm:max-w-md">
        <h1 class="mt-6 text-center text-3xl font-extrabold text-gray-900">
          Reset your password
        </h1>
      </div>

      <div class="mt-8 sm:mx-auto sm:w-full sm:max-w-md">
        <div class="bg-white py-8 px-4 shadow sm:rounded-lg sm:px-10">
          <%= if @success do %>
            <div
              class="rounded-md bg-green-50 p-4 mb-4"
              data-test-id="success-message"
              role="alert"
              aria-live="polite"
            >
              <div class="flex">
                <div class="flex-shrink-0">
                  <svg
                    class="h-5 w-5 text-green-400"
                    xmlns="http://www.w3.org/2000/svg"
                    viewBox="0 0 20 20"
                    fill="currentColor"
                  >
                    <path
                      fill-rule="evenodd"
                      d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"
                      clip-rule="evenodd"
                    />
                  </svg>
                </div>
                <div class="ml-3">
                  <p class="text-sm font-medium text-green-800">
                    Password reset successfully. Redirecting to login...
                  </p>
                </div>
              </div>
            </div>
          <% else %>
            <%= if @error_message do %>
              <div
                class="rounded-md bg-red-50 p-4 mb-4"
                data-test-id="error-message"
                role="alert"
                aria-live="polite"
              >
                <div class="flex">
                  <div class="flex-shrink-0">
                    <svg
                      class="h-5 w-5 text-red-400"
                      xmlns="http://www.w3.org/2000/svg"
                      viewBox="0 0 20 20"
                      fill="currentColor"
                    >
                      <path
                        fill-rule="evenodd"
                        d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z"
                        clip-rule="evenodd"
                      />
                    </svg>
                  </div>
                  <div class="ml-3">
                    <p class="text-sm font-medium text-red-800">
                      <%= @error_message %>
                    </p>
                  </div>
                </div>
              </div>
            <% end %>

            <%= if @token do %>
              <.form
                for={@form}
                id="reset_password_form"
                phx-change="validate"
                phx-submit="submit"
                data-test-id="reset-password-form"
              >
                <div class="space-y-6">
                  <div>
                    <label for="password" class="block text-sm font-medium text-gray-700">
                      New password
                    </label>
                    <div class="mt-1">
                      <.input
                        field={@form[:password]}
                        type="password"
                        required
                        phx-debounce="blur"
                        id="password"
                        data-test-id="password-input"
                        class="appearance-none block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm placeholder-gray-400 focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                      />
                      <.error :for={msg <- @form[:password].errors}><%= msg %></.error>
                    </div>
                  </div>

                  <div>
                    <label for="password_confirmation" class="block text-sm font-medium text-gray-700">
                      Confirm new password
                    </label>
                    <div class="mt-1">
                      <.input
                        field={@form[:password_confirmation]}
                        type="password"
                        required
                        phx-debounce="blur"
                        id="password_confirmation"
                        data-test-id="password-confirmation-input"
                        class="appearance-none block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm placeholder-gray-400 focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                      />
                      <.error :for={msg <- @form[:password_confirmation].errors}><%= msg %></.error>
                    </div>
                  </div>

                  <div>
                    <button
                      type="submit"
                      class="w-full flex justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 disabled:opacity-50"
                      disabled={@loading}
                      data-test-id="submit-button"
                    >
                      <%= if @loading do %>
                        <svg
                          class="animate-spin -ml-1 mr-3 h-5 w-5 text-white"
                          xmlns="http://www.w3.org/2000/svg"
                          fill="none"
                          viewBox="0 0 24 24"
                        >
                          <circle
                            class="opacity-25"
                            cx="12"
                            cy="12"
                            r="10"
                            stroke="currentColor"
                            stroke-width="4"
                          >
                          </circle>
                          <path
                            class="opacity-75"
                            fill="currentColor"
                            d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                          >
                          </path>
                        </svg>
                        Processing...
                      <% else %>
                        Reset Password
                      <% end %>
                    </button>
                  </div>
                </div>
              </.form>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
