defmodule OnelistWeb.Auth.PasswordResetComponent do
  use OnelistWeb, :live_component

  alias OnelistWeb.Auth.AuthLayoutComponent
  alias Onelist.Accounts

  def mount(socket) do
    {:ok,
     assign(socket,
       loading: false,
       error: nil,
       success: false,
       form_data: %{
         "email" => ""
       }
     )}
  end

  def handle_event("validate", %{"password_reset" => params}, socket) do
    error = validate_email(params["email"])
    {:noreply, assign(socket, error: error, form_data: params)}
  end

  def handle_event("submit", %{"password_reset" => params}, socket) do
    error = validate_email(params["email"])

    if error do
      {:noreply, assign(socket, error: error)}
    else
      # Set loading state
      socket = assign(socket, loading: true, error: nil)

      # Process the password reset request asynchronously
      %{"email" => email} = params
      Task.start(fn -> process_reset_request(email, self()) end)

      {:noreply, socket}
    end
  end

  def handle_info({:reset_processed, _result}, socket) do
    # We always show success regardless of the result for security
    # This prevents user enumeration attacks
    {:noreply,
     socket
     |> assign(loading: false)
     |> assign(success: true)}
  end

  # Process the reset request in a separate task
  defp process_reset_request(email, pid) do
    # Store connection info in process dictionary for tracking
    ip_address = Process.get(:current_ip_address, "unknown")
    user_agent = Process.get(:current_user_agent, "unknown")

    # Get the user by email
    result =
      case Accounts.get_user_by_email(email) do
        nil ->
          # If user doesn't exist, still log the attempt
          Accounts.track_login_attempt(
            email,
            nil,
            ip_address,
            user_agent,
            false,
            "reset_request_unknown_user"
          )

          :user_not_found

        user ->
          # Check if rate limited
          case Accounts.rate_limited?(email, ip_address) do
            {:ok, false} ->
              # Generate reset token and send email
              case Accounts.generate_reset_token(user) do
                {:ok, _user, _token} ->
                  # In a real implementation, we would send an email here
                  # For now, just log the attempt
                  Accounts.track_login_attempt(
                    email,
                    user,
                    ip_address,
                    user_agent,
                    true,
                    "reset_token_generated"
                  )

                  # TODO: Send email with token: OnelistWeb.Emails.reset_password(user, token) |> Onelist.Mailer.deliver_later()
                  :ok

                error ->
                  # Log failure
                  Accounts.track_login_attempt(
                    email,
                    user,
                    ip_address,
                    user_agent,
                    false,
                    "reset_token_generation_failed"
                  )

                  error
              end

            {:error, :rate_limited, _timeout} ->
              # Log rate limited attempt
              Accounts.track_login_attempt(
                email,
                user,
                ip_address,
                user_agent,
                false,
                "rate_limited"
              )

              :rate_limited
          end
      end

    # Send result back to component
    send(pid, {:reset_processed, result})
  end

  defp validate_email("") do
    "can't be blank"
  end

  defp validate_email(email) when is_binary(email) do
    case Regex.run(~r/^[^\s]+@[^\s]+$/, email) do
      nil -> "must have the @ sign and no spaces"
      _ -> nil
    end
  end

  defp validate_email(_) do
    "can't be blank"
  end

  def render(assigns) do
    ~H"""
    <div>
      <.live_component
        module={AuthLayoutComponent}
        id="auth-layout"
        page_title="Reset your password"
        page_description="Enter your email address to receive a password reset link"
      >
        <div data-test-id="password-reset-container">
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
                    If an account exists with that email address, you will receive a password reset link shortly.
                  </p>
                </div>
              </div>
            </div>
          <% end %>

          <form
            id="password-reset-form"
            phx-submit="submit"
            phx-change="validate"
            phx-target={@myself}
            data-test-id="password-reset-form"
            role="form"
            aria-label="Password reset form"
            class="space-y-6"
          >
            <div>
              <label for="email" class="block text-sm font-medium text-gray-700">
                Email address
              </label>
              <div class="mt-1">
                <input
                  type="email"
                  id="email"
                  name="password_reset[email]"
                  value={@form_data["email"]}
                  placeholder="Email"
                  required
                  class="appearance-none block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm placeholder-gray-400 focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                  data-test-id="email-input"
                  aria-required="true"
                  aria-invalid={@error != nil}
                  aria-describedby={if @error, do: "email-error"}
                />
              </div>

              <%= if @error do %>
                <div
                  class="mt-2 text-sm text-red-600"
                  role="alert"
                  id="email-error"
                  aria-live="polite"
                  data-test-id="email-error-message"
                >
                  <%= @error %>
                </div>
              <% end %>
            </div>

            <div>
              <button
                type="submit"
                class="w-full flex justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 disabled:opacity-50"
                data-test-id="submit-button"
                disabled={@loading}
                aria-busy={@loading}
                phx-disable-with="Sending..."
              >
                <%= if @loading do %>
                  <div data-test-id="loading-indicator">
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
                    Sending...
                  </div>
                <% else %>
                  Send password reset link
                <% end %>
              </button>
            </div>
          </form>

          <div class="mt-6">
            <p class="text-center text-sm text-gray-600">
              <a
                href={~p"/login"}
                data-test-id="back-to-login"
                class="font-medium text-indigo-600 hover:text-indigo-500"
              >
                Back to login
              </a>
            </p>
          </div>

          <%= if @loading do %>
            <div data-test-id="loading-announcement" class="sr-only" aria-live="polite">
              Loading...
            </div>
          <% end %>
        </div>
      </.live_component>
    </div>
    """
  end
end
