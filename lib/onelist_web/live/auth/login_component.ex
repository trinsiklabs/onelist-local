defmodule OnelistWeb.Auth.LoginComponent do
  use OnelistWeb, :live_component

  alias OnelistWeb.Auth.AuthLayoutComponent
  alias OnelistWeb.Auth.Components.SocialLoginButtonsComponent

  def mount(socket) do
    {:ok,
     assign(socket,
       loading: false,
       form_data: %{
         "email" => "",
         "password" => "",
         "remember_me" => "false"
       },
       errors: %{}
     )}
  end

  def handle_event("validate", %{"user" => params}, socket) do
    errors = validate_form(params)
    {:noreply, assign(socket, errors: errors, form_data: params)}
  end

  def handle_event("submit", %{"user" => params}, socket) do
    case validate_form(params) do
      errors when map_size(errors) == 0 ->
        # In a real implementation, we would authenticate the user here
        # For now, we'll just simulate a successful login
        {:noreply,
         socket
         |> assign(loading: true)
         |> put_flash(:info, "Welcome back!")
         |> redirect(to: "/dashboard")}

      errors ->
        {:noreply, assign(socket, errors: errors)}
    end
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
        errors
      end

    # Simulate invalid credentials error
    if params["email"] == "test@example.com" && params["password"] == "wrongpassword" do
      Map.put(errors, :credentials, "Invalid email or password")
    else
      errors
    end
  end

  def render(assigns) do
    ~H"""
    <div>
      <.live_component
        module={AuthLayoutComponent}
        id="auth-layout"
        page_title="Sign in to your account"
        page_description="Welcome back to Onelist"
      >
        <form
          id="login-form"
          data-test-id="login-form"
          action="/login"
          method="post"
          phx-change="validate"
          phx-target={@myself}
        >
          <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
          <div class="space-y-6">
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
                  autocomplete="current-password"
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
            </div>

            <%= if @errors[:credentials] do %>
              <p class="mt-2 text-sm text-red-600" role="alert">
                <%= @errors[:credentials] %>
              </p>
            <% end %>

            <div class="flex items-center justify-between">
              <div class="flex items-center">
                <input
                  id="remember_me"
                  name="user[remember_me]"
                  type="checkbox"
                  class="h-4 w-4 text-indigo-600 focus:ring-indigo-500 border-gray-300 rounded"
                  data-test-id="remember-me-checkbox"
                  aria-label="Remember me"
                  checked={@form_data["remember_me"] == "true"}
                />
                <label for="remember_me" class="ml-2 block text-sm text-gray-900">
                  Remember me
                </label>
              </div>

              <div class="text-sm">
                <a
                  href="/forgot-password"
                  class="font-medium text-indigo-600 hover:text-indigo-500"
                  data-test-id="forgot-password-link"
                >
                  Forgot your password?
                </a>
              </div>
            </div>

            <div>
              <button
                type="submit"
                class="w-full flex justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 disabled:opacity-50"
                data-test-id={if @loading, do: "login-button-loading", else: "login-button"}
                disabled={@loading}
                aria-live="polite"
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
                  Signing in...
                <% else %>
                  Sign in
                <% end %>
              </button>
            </div>

            <.live_component module={SocialLoginButtonsComponent} id="social-login-buttons" />

            <div class="mt-6">
              <p class="text-center text-sm text-gray-600">
                Don't have an account?
                <a
                  href="/register"
                  data-test-id="register-link"
                  class="font-medium text-indigo-600 hover:text-indigo-500"
                >
                  Sign up
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
