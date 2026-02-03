defmodule OnelistWeb.Auth.PasswordResetPage do
  use OnelistWeb, :live_view

  alias OnelistWeb.Auth.PasswordResetComponent

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Reset your password")}
  end

  def render(assigns) do
    ~H"""
    <div>
      <.live_component module={PasswordResetComponent} id="password-reset" />
    </div>
    """
  end
end
