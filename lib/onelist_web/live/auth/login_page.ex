defmodule OnelistWeb.Auth.LoginPage do
  use OnelistWeb, :live_view

  alias OnelistWeb.Auth.LoginComponent

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Sign in to your account")}
  end

  def render(assigns) do
    ~H"""
    <div>
      <.live_component
        module={LoginComponent}
        id="login"
      />
    </div>
    """
  end
end 