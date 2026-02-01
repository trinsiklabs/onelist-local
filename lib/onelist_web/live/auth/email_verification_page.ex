defmodule OnelistWeb.Auth.EmailVerificationPage do
  use OnelistWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Verify Your Email")}
  end

  def handle_params(%{"token" => token}, _url, socket) do
    accounts = Application.get_env(:onelist, :accounts, Onelist.Accounts)
    case accounts.verify_email(token) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Email verified successfully. You can now log in.")
         |> redirect(to: ~p"/login")}

      {:error, :invalid_token} ->
        {:noreply,
         socket
         |> put_flash(:error, "Invalid verification link. Please request a new one.")
         |> redirect(to: ~p"/verify-email")}

      {:error, :expired_token} ->
        {:noreply,
         socket
         |> put_flash(:error, "Verification link has expired. Please request a new one.")
         |> redirect(to: ~p"/verify-email")}
         
      {:error, _} ->
        # Handle any other errors (including server errors) with a generic message
        {:noreply,
         socket
         |> put_flash(:error, "There was a problem verifying your email. Please try again later.")
         |> redirect(to: ~p"/verify-email")}
    end
  end

  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm" data-test-id="email-verification-page">
      <.live_component
        module={OnelistWeb.Auth.EmailVerificationComponent}
        id="email-verification"
      />
    </div>
    """
  end
end 