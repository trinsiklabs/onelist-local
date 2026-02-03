defmodule OnelistWeb.Auth.Components.SocialLoginButtonsComponent do
  @moduledoc """
  Component for rendering social login buttons with proper styling.
  Supports GitHub, Google, and Apple Sign In.
  """

  use OnelistWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div class="social-login-container" data-test-id="social-login-buttons">
      <div class="social-login-divider">
        <span>or continue with</span>
      </div>

      <div class="social-login-buttons">
        <button
          class="social-button github-button"
          phx-click="oauth-request"
          phx-value-provider="github"
          phx-target={@myself}
          data-test-id="github-login-button"
        >
          <div class="button-content">
            <svg class="github-icon" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
              <path d="M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12" />
            </svg>
            <span>GitHub</span>
          </div>
        </button>

        <button
          class="social-button google-button"
          phx-click="oauth-request"
          phx-value-provider="google"
          phx-target={@myself}
          data-test-id="google-login-button"
        >
          <div class="button-content">
            <svg class="google-icon" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
              <path d="M12.24 10.285V14.4h6.806c-.275 1.765-2.056 5.174-6.806 5.174-4.095 0-7.439-3.389-7.439-7.574s3.345-7.574 7.439-7.574c2.33 0 3.891.989 4.785 1.849l3.254-3.138C18.189 1.186 15.479 0 12.24 0c-6.635 0-12 5.365-12 12s5.365 12 12 12c6.926 0 11.52-4.869 11.52-11.726 0-.788-.085-1.39-.189-1.989H12.24z" />
            </svg>
            <span>Google</span>
          </div>
        </button>

        <button
          class="social-button apple-button"
          phx-click="oauth-request"
          phx-value-provider="apple"
          phx-target={@myself}
          data-test-id="apple-login-button"
        >
          <div class="button-content">
            <svg class="apple-icon" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
              <path d="M17.569 12.6254C17.597 15.4891 20.2179 16.3841 20.247 16.3969C20.2248 16.4718 19.9355 17.4363 19.1767 18.4359C18.5373 19.2859 17.8665 20.1315 16.8428 20.1527C15.8413 20.173 15.4636 19.5955 14.3133 19.5955C13.1629 19.5955 12.7449 20.1315 11.8028 20.173C10.8179 20.2144 10.0544 19.2683 9.40547 18.4227C8.0679 16.6945 7.02856 13.5205 8.40513 11.3996C9.087 10.3527 10.2578 9.70168 11.5269 9.68045C12.4899 9.6592 13.3915 10.2991 13.9903 10.2991C14.5892 10.2991 15.6948 9.53727 16.8643 9.65402C17.2611 9.67128 18.5162 9.82861 19.3441 10.9308C19.2795 10.9713 17.5451 11.9714 17.569 12.6254ZM15.5227 7.3949C16.0601 6.75242 16.4133 5.85786 16.3031 4.9633C15.5399 4.99685 14.5915 5.46209 14.0328 6.08279C13.5368 6.62835 13.1088 7.55469 13.2401 8.41746C14.0964 8.48195 14.9657 8.0344 15.5227 7.3949Z" />
            </svg>
            <span>Apple</span>
          </div>
        </button>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("oauth-request", %{"provider" => provider}, socket) do
    # Redirect to the OAuth request endpoint
    path = ~p"/auth/#{provider}"

    {:noreply, push_navigate(socket, to: path)}
  end
end
