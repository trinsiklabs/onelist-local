defmodule OnelistWeb.Plugs.SecurityHeaders do
  @moduledoc """
  Plug to add additional security headers to responses.

  This plug adds Content-Security-Policy and other security headers
  that complement Phoenix's default :put_secure_browser_headers.
  """

  import Plug.Conn

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    conn
    |> put_csp_header()
    |> put_permissions_policy_header()
  end

  defp put_csp_header(conn) do
    # Content-Security-Policy header
    # Note: This is a baseline policy. Adjust based on your application's needs.
    csp_directives = [
      "default-src 'self'",
      # Allow inline styles for Phoenix LiveView and Tailwind
      "style-src 'self' 'unsafe-inline'",
      # Allow inline scripts for Phoenix LiveView (consider using nonces in production)
      "script-src 'self' 'unsafe-inline' 'unsafe-eval'",
      # Allow images from self and data URIs
      "img-src 'self' data: https:",
      # Allow fonts from self
      "font-src 'self' data:",
      # Allow WebSocket connections for LiveView
      "connect-src 'self' wss: ws:",
      # Prevent framing (clickjacking protection)
      "frame-ancestors 'none'",
      # Form submissions only to self
      "form-action 'self'",
      # Base URI restriction
      "base-uri 'self'",
      # Block mixed content
      "upgrade-insecure-requests"
    ]

    put_resp_header(conn, "content-security-policy", Enum.join(csp_directives, "; "))
  end

  defp put_permissions_policy_header(conn) do
    # Permissions-Policy (formerly Feature-Policy)
    # Restricts access to browser features
    permissions = [
      "accelerometer=()",
      "camera=()",
      "geolocation=()",
      "gyroscope=()",
      "magnetometer=()",
      "microphone=()",
      "payment=()",
      "usb=()"
    ]

    put_resp_header(conn, "permissions-policy", Enum.join(permissions, ", "))
  end
end
