defmodule OnelistWeb.Auth.EmailVerificationComponent do
  use OnelistWeb, :live_component

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm" data-test-id="email-verification-component">
      <div class="text-center">
        <h1 class="text-lg font-semibold leading-8 text-zinc-800">
          Verify Your Email
        </h1>
        <p class="mt-2 text-sm leading-6 text-zinc-600">
          We've sent you an email with a verification link. Please check your inbox and click the link to verify your email address.
        </p>
      </div>

      <div class="space-y-4 text-center text-sm">
        <p>
          Didn't receive the email?
          <.link
            href={~p"/resend-verification"}
            class="font-semibold text-brand hover:underline"
            data-test-id="resend-verification-link"
            aria-label="Resend verification email"
          >
            Click here to resend
          </.link>
        </p>
      </div>
    </div>
    """
  end
end 