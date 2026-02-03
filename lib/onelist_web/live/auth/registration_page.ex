defmodule OnelistWeb.Auth.RegistrationPage do
  use OnelistWeb, :live_view

  alias OnelistWeb.Auth.RegistrationComponent

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Sign up - Onelist")}
  end

  def render(assigns) do
    ~H"""
    <.live_component module={RegistrationComponent} id="registration" />
    """
  end
end
