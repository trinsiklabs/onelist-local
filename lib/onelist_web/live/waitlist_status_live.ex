defmodule OnelistWeb.WaitlistStatusLive do
  @moduledoc """
  LiveView for checking waitlist status.
  """

  use OnelistWeb, :live_view

  alias Onelist.Waitlist

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    case Waitlist.get_signup_by_token(token) do
      nil ->
        socket =
          socket
          |> assign(:page_title, "Not Found")
          |> assign(:signup, nil)
          |> assign(:position_info, nil)
        
        {:ok, socket}
      
      signup ->
        position_info = Waitlist.get_position_info(signup)
        
        socket =
          socket
          |> assign(:page_title, "Your Headwaters Status")
          |> assign(:signup, signup)
          |> assign(:position_info, position_info)
        
        {:ok, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-b from-slate-900 via-slate-800 to-slate-900">
      <div class="max-w-2xl mx-auto px-4 py-16 sm:py-24">
        
        <%= if @signup do %>
          <.status_view signup={@signup} position_info={@position_info} />
        <% else %>
          <.not_found_view />
        <% end %>
        
      </div>
    </div>
    """
  end

  defp status_view(assigns) do
    ~H"""
    <div class="text-center">
      <!-- Header -->
      <div class="mb-8">
        <span class="text-5xl">🌊</span>
      </div>
      
      <h1 class="text-3xl sm:text-4xl font-bold text-white mb-2">
        <%= status_title(@signup.status) %>
      </h1>
      
      <p class="text-lg text-slate-400 mb-8">
        <%= if @signup.name, do: @signup.name, else: @signup.email %>
      </p>
      
      <!-- Main Status Card -->
      <div class="bg-slate-800/50 rounded-2xl p-8 mb-8 border border-slate-700">
        
        <%= case @signup.status do %>
          <% "waiting" -> %>
            <.waiting_status position_info={@position_info} />
          <% "invited" -> %>
            <.invited_status signup={@signup} />
          <% "activated" -> %>
            <.activated_status signup={@signup} />
          <% _ -> %>
            <p class="text-slate-400">Status: <%= @signup.status %></p>
        <% end %>
        
      </div>
      
      <!-- Timeline -->
      <div class="bg-slate-800/30 rounded-xl p-6">
        <h3 class="text-sm font-medium text-slate-400 mb-4">Your Journey</h3>
        <.timeline signup={@signup} />
      </div>
      
    </div>
    """
  end

  defp waiting_status(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Big Number -->
      <div>
        <div class="text-6xl font-bold text-cyan-400 mb-2">
          #<%= @position_info.queue_number %>
        </div>
        <div class="text-slate-400">of <%= @position_info.max_spots %> Headwaters</div>
      </div>
      
      <!-- Stats Grid -->
      <div class="grid grid-cols-3 gap-4 py-6 border-y border-slate-700">
        <div>
          <div class="text-2xl font-bold text-white"><%= @position_info.activated_count %></div>
          <div class="text-xs text-slate-500">Activated</div>
        </div>
        <div>
          <div class="text-2xl font-bold text-amber-400"><%= @position_info.invited_count %></div>
          <div class="text-xs text-slate-500">Invited</div>
        </div>
        <div>
          <div class="text-2xl font-bold text-emerald-400"><%= @position_info.ahead_in_queue %></div>
          <div class="text-xs text-slate-500">Ahead of You</div>
        </div>
      </div>
      
      <!-- Estimated Wait -->
      <div>
        <div class="text-slate-400 mb-1">Estimated wait</div>
        <div class="text-2xl font-semibold text-white"><%= @position_info.estimated_wait %></div>
      </div>
      
      <!-- Progress Bar -->
      <div class="pt-4">
        <div class="flex justify-between text-xs text-slate-500 mb-2">
          <span>Progress</span>
          <span><%= @position_info.activated_count %>/<%= @position_info.queue_number %></span>
        </div>
        <div class="h-2 bg-slate-700 rounded-full overflow-hidden">
          <div 
            class="h-full bg-gradient-to-r from-cyan-500 to-blue-500 transition-all duration-500"
            style={"width: #{progress_percent(@position_info)}%"}
          >
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp invited_status(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="text-5xl mb-4">🎉</div>
      
      <div>
        <div class="text-2xl font-bold text-emerald-400 mb-2">You're Invited!</div>
        <p class="text-slate-300">
          Check your email for instructions to create your account.
        </p>
      </div>
      
      <div class="pt-4">
        <a 
          href="/signup"
          class="inline-block py-3 px-8 bg-gradient-to-r from-emerald-500 to-cyan-500 hover:from-emerald-400 hover:to-cyan-400 text-white font-semibold rounded-lg transition-all"
        >
          Create Your Account →
        </a>
      </div>
      
      <p class="text-sm text-slate-500">
        Invited on <%= Calendar.strftime(@signup.invited_at, "%B %d, %Y") %>
      </p>
    </div>
    """
  end

  defp activated_status(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="text-5xl mb-4">✨</div>
      
      <div>
        <div class="text-2xl font-bold text-cyan-400 mb-2">Welcome, Headwater!</div>
        <p class="text-slate-300">
          Your account is active. Thanks for being an early believer.
        </p>
      </div>
      
      <div class="pt-4">
        <a 
          href="/app"
          class="inline-block py-3 px-8 bg-gradient-to-r from-cyan-500 to-blue-500 hover:from-cyan-400 hover:to-blue-400 text-white font-semibold rounded-lg transition-all"
        >
          Go to Onelist →
        </a>
      </div>
      
      <p class="text-sm text-slate-500">
        Headwater #<%= @signup.queue_number %> since <%= Calendar.strftime(@signup.activated_at, "%B %d, %Y") %>
      </p>
    </div>
    """
  end

  defp timeline(assigns) do
    ~H"""
    <div class="flex flex-col gap-4">
      <!-- Signed Up -->
      <div class="flex items-center gap-3">
        <div class="w-3 h-3 rounded-full bg-cyan-500"></div>
        <div class="flex-1 text-left">
          <div class="text-sm text-white">Joined Waitlist</div>
          <div class="text-xs text-slate-500">
            <%= Calendar.strftime(@signup.inserted_at, "%B %d, %Y at %I:%M %p") %>
          </div>
        </div>
      </div>
      
      <!-- Invited -->
      <div class="flex items-center gap-3">
        <div class={"w-3 h-3 rounded-full #{if @signup.invited_at, do: "bg-emerald-500", else: "bg-slate-600"}"}></div>
        <div class="flex-1 text-left">
          <div class={"text-sm #{if @signup.invited_at, do: "text-white", else: "text-slate-500"}"}>
            Invitation Sent
          </div>
          <%= if @signup.invited_at do %>
            <div class="text-xs text-slate-500">
              <%= Calendar.strftime(@signup.invited_at, "%B %d, %Y at %I:%M %p") %>
            </div>
          <% else %>
            <div class="text-xs text-slate-600">Waiting...</div>
          <% end %>
        </div>
      </div>
      
      <!-- Activated -->
      <div class="flex items-center gap-3">
        <div class={"w-3 h-3 rounded-full #{if @signup.activated_at, do: "bg-cyan-400", else: "bg-slate-600"}"}></div>
        <div class="flex-1 text-left">
          <div class={"text-sm #{if @signup.activated_at, do: "text-white", else: "text-slate-500"}"}>
            Account Activated
          </div>
          <%= if @signup.activated_at do %>
            <div class="text-xs text-slate-500">
              <%= Calendar.strftime(@signup.activated_at, "%B %d, %Y at %I:%M %p") %>
            </div>
          <% else %>
            <div class="text-xs text-slate-600">Pending</div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp not_found_view(assigns) do
    ~H"""
    <div class="text-center">
      <div class="text-5xl mb-6">🔍</div>
      <h1 class="text-2xl font-bold text-white mb-4">Status Not Found</h1>
      <p class="text-slate-400 mb-8">
        This status link doesn't exist or may have expired.
      </p>
      <a 
        href="/waitlist"
        class="inline-block py-3 px-6 bg-slate-700 hover:bg-slate-600 text-white rounded-lg transition"
      >
        Join the Waitlist →
      </a>
    </div>
    """
  end

  defp status_title("waiting"), do: "You're on the List"
  defp status_title("invited"), do: "You're Invited!"
  defp status_title("activated"), do: "Welcome Aboard"
  defp status_title(_), do: "Your Status"

  defp progress_percent(%{activated_count: activated, queue_number: number}) when number > 0 do
    min(round(activated / number * 100), 100)
  end
  defp progress_percent(_), do: 0
end
