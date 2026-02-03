defmodule OnelistWeb.HomePage do
  use OnelistWeb, :live_view

  alias OnelistWeb.{Navigation, HeroSection, Footer}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Welcome to Onelist")
     |> assign(:current_user, nil)
     |> assign(:current_page, :home)}
  end

  def handle_event("signup", _params, socket) do
    {:noreply, push_navigate(socket, to: "/register")}
  end

  def handle_event("login", _params, socket) do
    {:noreply, push_navigate(socket, to: "/login")}
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-white">
      <.live_component
        module={Navigation}
        id="main-nav"
        current_user={@current_user}
        current_page={@current_page}
      />

      <.live_component module={HeroSection} id="main-hero" />

      <.live_component module={Footer} id="main-footer" />
    </div>
    """
  end
end
