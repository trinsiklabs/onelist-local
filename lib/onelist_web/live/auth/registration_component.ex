defmodule OnelistWeb.Auth.RegistrationComponent do
  use OnelistWeb, :live_component

  alias OnelistWeb.Auth.AuthLayoutComponent
  alias OnelistWeb.Auth.Components.SocialLoginButtonsComponent
  alias Onelist.Accounts
  alias Onelist.Privacy

  @impl true
  def mount(socket) do
    # Extract connection info during mount (only time it's available)
    user_agent = get_connect_info_safely(socket, :user_agent) || "unknown"
    client_ip = extract_client_ip(socket)
    
    {:ok,
     assign(socket,
       loading: false,
       form_data: %{
         "email" => "",
         "password" => "",
         "password_confirmation" => ""
       },
       errors: %{},
       user_agent: user_agent,
       client_ip: client_ip
     )}
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    errors = validate_form(params)
    {:noreply, assign(socket, errors: errors, form_data: params)}
  end

  @impl true
  def handle_event("submit", %{"user" => params}, socket) do
    case validate_form(params) do
      errors when map_size(errors) == 0 ->
        # Mark loading to show UI feedback
        socket = assign(socket, loading: true)

        # Store request information in process dictionary for tracking
        store_request_info_from_assigns(socket)

        # Process registration synchronously
        case register_user(params) do
          {:ok, user} ->
            # Log successful registration without revealing sensitive data
            Privacy.log_privacy_action(:user_registered, %{user_id: user.id})

            # Send registration confirmation email asynchronously
            send_confirmation_email(user)

            # Redirect to email verification page
            {:noreply,
             socket
             |> put_flash(:info, "Registration successful! Please check your email to verify your account.")
             |> redirect(to: ~p"/verify-email")}

          {:error, %Ecto.Changeset{} = changeset} ->
            # Handle changeset errors
            errors = changeset_to_errors(changeset)
            {:noreply, assign(socket, loading: false, errors: errors, form_data: params)}

          {:error, reason} ->
            # Log failed registration without revealing sensitive data
            Privacy.log_privacy_action(:registration_failed, %{reason: reason})

            errors = case reason do
              :email_taken ->
                Map.put(%{}, :email, "email already registered")

              :invalid_password ->
                Map.put(%{}, :password, "doesn't meet security requirements")

              _ ->
                Map.put(%{}, :base, "An error occurred. Please try again.")
            end

            {:noreply, assign(socket, loading: false, errors: errors, form_data: params)}
        end

      errors ->
        {:noreply, assign(socket, errors: errors)}
    end
  end

  defp get_connect_info_safely(socket, key) do
    try do
      Phoenix.LiveView.get_connect_info(socket, key)
    rescue
      _ -> nil
    end
  end

  defp extract_client_ip(socket) do
    case get_connect_info_safely(socket, :peer_data) do
      %{address: address} when is_tuple(address) -> 
        address |> Tuple.to_list() |> Enum.join(".")
      _ -> 
        "unknown"
    end
  end

  defp store_request_info_from_assigns(socket) do
    # Use connection info from assigns
    Process.put(:current_ip_address, socket.assigns.client_ip)
    Process.put(:current_user_agent, socket.assigns.user_agent)
  end

  defp register_user(params) do
    # Create user with proper error handling
    Accounts.create_user(%{
      email: params["email"],
      password: params["password"]
    })
  end

  defp send_confirmation_email(_user) do
    # Placeholder for sending confirmation email
    # Will be implemented when email delivery is set up
    # OnelistWeb.Emails.confirmation_email(user)
    # |> Onelist.Mailer.deliver_later()
    :ok
  end

  defp changeset_to_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.reduce(%{}, fn {field, messages}, acc ->
      Map.put(acc, field, Enum.join(messages, ", "))
    end)
  end

  defp validate_form(params) do
    errors = %{}

    errors =
      if String.length(params["email"] || "") == 0 do
        Map.put(errors, :email, "can't be blank")
      else
        if String.match?(params["email"] || "", ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/) do
          errors
        else
          Map.put(errors, :email, "must be a valid email")
        end
      end

    errors =
      if String.length(params["password"] || "") == 0 do
        Map.put(errors, :password, "can't be blank")
      else
        if String.length(params["password"] || "") < 8 do
          Map.put(errors, :password, "at least 8 characters")
        else
          # Check for more complex password requirements
          password = params["password"] || ""
          cond do
            # Check for uppercase
            !String.match?(password, ~r/[A-Z]/) ->
              Map.put(errors, :password, "must include at least one uppercase letter")
              
            # Check for number
            !String.match?(password, ~r/[0-9]/) ->
              Map.put(errors, :password, "must include at least one number")
              
            # Check for special character
            !String.match?(password, ~r/[^a-zA-Z0-9]/) ->
              Map.put(errors, :password, "must include at least one special character")
              
            true ->
              errors
          end
        end
      end

    errors =
      if params["password"] != params["password_confirmation"] do
        Map.put(errors, :password_confirmation, "passwords do not match")
      else
        errors
      end

    errors
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.live_component
        module={AuthLayoutComponent}
        id="auth-layout"
        page_title="Create your account"
        page_description="Start organizing your notes today"
      >
        <form 
          id="registration-form" 
          data-test-id="registration-form"
          phx-submit="submit" 
          phx-change="validate" 
          phx-target={@myself}
        >
          <div class="space-y-6">
            <%= if @errors[:base] do %>
              <div class="rounded-md bg-red-50 p-4" role="alert" data-test-id="form-error">
                <div class="flex">
                  <div class="flex-shrink-0">
                    <svg class="h-5 w-5 text-red-400" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
                      <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.28 7.22a.75.75 0 00-1.06 1.06L8.94 10l-1.72 1.72a.75.75 0 101.06 1.06L10 11.06l1.72 1.72a.75.75 0 101.06-1.06L11.06 10l1.72-1.72a.75.75 0 00-1.06-1.06L10 8.94 8.28 7.22z" clip-rule="evenodd" />
                    </svg>
                  </div>
                  <div class="ml-3">
                    <h3 class="text-sm font-medium text-red-800"><%= @errors[:base] %></h3>
                  </div>
                </div>
              </div>
            <% end %>

            <div>
              <label for="email" class="block text-sm font-medium text-gray-700">
                Email address
              </label>
              <div class="mt-1">
                <input
                  id="email"
                  name="user[email]"
                  type="email"
                  autocomplete="email"
                  required
                  class="appearance-none block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm placeholder-gray-400 focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                  data-test-id="email-input"
                  aria-label="Email address"
                  value={@form_data["email"]}
                  aria-invalid={@errors[:email] != nil}
                  aria-describedby={if @errors[:email], do: "email-error"}
                />
              </div>
              <%= if @errors[:email] do %>
                <p class="mt-2 text-sm text-red-600" id="email-error" role="alert">
                  <%= @errors[:email] %>
                </p>
              <% end %>
            </div>

            <div>
              <label for="password" class="block text-sm font-medium text-gray-700">
                Password
              </label>
              <div class="mt-1">
                <input
                  id="password"
                  name="user[password]"
                  type="password"
                  autocomplete="new-password"
                  required
                  class="appearance-none block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm placeholder-gray-400 focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                  data-test-id="password-input"
                  aria-label="Password"
                  value={@form_data["password"]}
                  aria-invalid={@errors[:password] != nil}
                  aria-describedby={if @errors[:password], do: "password-error"}
                />
              </div>
              <%= if @errors[:password] do %>
                <p class="mt-2 text-sm text-red-600" id="password-error" role="alert">
                  <%= @errors[:password] %>
                </p>
              <% end %>
              <div class="mt-2">
                <ul class="text-sm text-gray-600 space-y-1">
                  <li>At least 8 characters</li>
                  <li>At least one uppercase letter</li>
                  <li>At least one number</li>
                  <li>At least one special character</li>
                </ul>
              </div>
            </div>

            <div>
              <label for="password_confirmation" class="block text-sm font-medium text-gray-700">
                Confirm password
              </label>
              <div class="mt-1">
                <input
                  id="password_confirmation"
                  name="user[password_confirmation]"
                  type="password"
                  autocomplete="new-password"
                  required
                  class="appearance-none block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm placeholder-gray-400 focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                  data-test-id="password-confirmation-input"
                  aria-label="Confirm password"
                  value={@form_data["password_confirmation"]}
                  aria-invalid={@errors[:password_confirmation] != nil}
                  aria-describedby={if @errors[:password_confirmation], do: "password-confirmation-error"}
                />
              </div>
              <%= if @errors[:password_confirmation] do %>
                <p class="mt-2 text-sm text-red-600" id="password-confirmation-error" role="alert">
                  <%= @errors[:password_confirmation] %>
                </p>
              <% end %>
            </div>

            <div>
              <button
                type="submit"
                class="w-full flex justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 disabled:opacity-50"
                data-test-id={if @loading, do: "register-button-loading", else: "register-button"}
                disabled={@loading}
                aria-live="polite"
              >
                <%= if @loading do %>
                  <svg class="animate-spin -ml-1 mr-3 h-5 w-5 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                    <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                    <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                  </svg>
                  Creating account...
                <% else %>
                  Create account
                <% end %>
              </button>
            </div>

            <.live_component
              module={SocialLoginButtonsComponent}
              id="social-login-buttons"
            />

            <div class="mt-6">
              <p class="text-center text-sm text-gray-600">
                By signing up, you agree to our
                <a href="/terms" data-test-id="terms-link" class="font-medium text-indigo-600 hover:text-indigo-500">
                  Terms
                </a>
                and
                <a href="/privacy" data-test-id="privacy-link" class="font-medium text-indigo-600 hover:text-indigo-500">
                  Privacy Policy
                </a>
              </p>
            </div>
          </div>
        </form>
      </.live_component>
    </div>
    """
  end
end 