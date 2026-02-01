defmodule OnelistWeb.WaitlistLive do
  @moduledoc """
  LiveView for the Headwaters waitlist signup.
  """

  use OnelistWeb, :live_view

  alias Onelist.Waitlist
  alias Onelist.Waitlist.Signup

  @impl true
  def mount(_params, _session, socket) do
    # Subscribe to waitlist updates for live counter
    if connected?(socket) do
      Waitlist.subscribe()
    end
    
    total = Waitlist.count_signups()
    next_number = total + 1
    
    socket =
      socket
      |> assign(:page_title, "Join the Headwaters")
      |> assign(:total_signups, total)
      |> assign(:next_number, next_number)
      |> assign(:tier_info, get_tier_info(next_number))
      |> assign(:form, to_form(Waitlist.Signup.changeset(%Signup{}, %{})))
      |> assign(:submitted, false)
      |> assign(:signup, nil)
    
    {:ok, socket}
  end

  @impl true
  def handle_info({:waitlist_updated, %{remaining: _remaining, total: total}}, socket) do
    next_number = total + 1
    
    socket =
      socket
      |> assign(:total_signups, total)
      |> assign(:next_number, next_number)
      |> assign(:tier_info, get_tier_info(next_number))
    
    {:noreply, socket}
  end

  defp get_tier_info(number) when number <= 100 do
    %{
      name: "Headwaters",
      emoji: "🌊",
      spots_in_tier: 100,
      spots_remaining: 100 - number + 1,
      description: "The first 100 — where it all begins",
      badge_class: "from-cyan-500 to-blue-500"
    }
  end

  defp get_tier_info(number) when number <= 1000 do
    %{
      name: "Tributaries",
      emoji: "💧",
      spots_in_tier: 900,
      spots_remaining: 1000 - number + 1,
      description: "Early adopters shaping the flow",
      badge_class: "from-emerald-500 to-teal-500"
    }
  end

  defp get_tier_info(_number) do
    %{
      name: "Public",
      emoji: "🌍",
      spots_in_tier: nil,
      spots_remaining: nil,
      description: "Welcome to Onelist",
      badge_class: "from-slate-500 to-slate-600"
    }
  end

  @impl true
  def handle_event("validate", %{"signup" => params}, socket) do
    changeset =
      %Signup{}
      |> Signup.changeset(params)
      |> Map.put(:action, :validate)
    
    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("submit", %{"signup" => params}, socket) do
    email = params["email"] || ""
    
    # Check if already registered
    case Waitlist.get_signup_by_email(email) do
      %Waitlist.Signup{} = existing ->
        # Already signed up - show their existing signup
        socket =
          socket
          |> assign(:submitted, true)
          |> assign(:signup, existing)
          |> assign(:position_info, Waitlist.get_position_info(existing))
          |> put_flash(:info, "Welcome back! You're already on the list.")
        
        {:noreply, socket}
      
      nil ->
        # New signup
        case Waitlist.create_signup(params) do
          {:ok, signup} ->
            socket =
              socket
              |> assign(:submitted, true)
              |> assign(:signup, signup)
              |> assign(:position_info, Waitlist.get_position_info(signup))
            
            {:noreply, socket}
          
          {:error, :waitlist_full} ->
            socket =
              socket
              |> put_flash(:error, "Sorry, the waitlist is now full!")
            
            {:noreply, socket}
          
          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign(socket, :form, to_form(changeset))}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-b from-slate-900 via-slate-800 to-slate-900">
      <div class="max-w-2xl mx-auto px-4 py-16 sm:py-24">
        
        <%= if @submitted do %>
          <!-- Success State -->
          <.success_view signup={@signup} position_info={@position_info} tier_info={get_tier_info(@signup.queue_number)} />
        <% else %>
          <!-- Signup Form -->
          <.signup_form 
            form={@form} 
            next_number={@next_number}
            tier_info={@tier_info}
          />
        <% end %>
        
      </div>
    </div>
    """
  end

  defp success_view(assigns) do
    ~H"""
    <div class="text-center">
      <!-- Celebration -->
      <div class="mb-6">
        <span class="text-6xl"><%= @tier_info.emoji %></span>
      </div>
      
      <h1 class="text-4xl font-bold text-white mb-4">
        Welcome to the <%= @tier_info.name %>
      </h1>
      
      <p class="text-xl text-slate-300 mb-6">
        You're <span class={"font-bold bg-gradient-to-r #{@tier_info.badge_class} bg-clip-text text-transparent"}>#<%= @signup.queue_number %></span>
      </p>
      
      <!-- Your Number Card -->
      <div class="bg-slate-800/50 rounded-2xl p-6 mb-6 border border-slate-700 inline-block">
        <div class="text-5xl font-bold text-white mb-1">#<%= @signup.queue_number %></div>
        <div class="text-slate-400"><%= @tier_info.name %></div>
      </div>
      
      <!-- Rollout Explanation -->
      <div class="bg-slate-800/30 rounded-2xl p-6 mb-6 border border-slate-700 text-left max-w-lg mx-auto">
        <h3 class="text-lg font-semibold text-white mb-4">How we're rolling out</h3>
        
        <div class="space-y-4">
          <!-- Headwaters -->
          <div class={"flex gap-3 " <> if(@signup.queue_number <= 100, do: "opacity-100", else: "opacity-50")}>
            <div class="text-2xl">🌊</div>
            <div>
              <div class="font-medium text-white">Headwaters <span class="text-cyan-400">#1–100</span></div>
              <div class="text-sm text-slate-400">First access while we stabilize infrastructure and squash bugs</div>
              <%= if @signup.queue_number <= 100 do %>
                <div class="text-xs text-cyan-400 mt-1">← You're here!</div>
              <% end %>
            </div>
          </div>
          
          <!-- Tributaries -->
          <div class={"flex gap-3 " <> if(@signup.queue_number > 100 && @signup.queue_number <= 1000, do: "opacity-100", else: "opacity-50")}>
            <div class="text-2xl">💧</div>
            <div>
              <div class="font-medium text-white">Tributaries <span class="text-emerald-400">#101–1000</span></div>
              <div class="text-sm text-slate-400">Opens after Headwaters, activated in waves as we scale</div>
              <%= if @signup.queue_number > 100 && @signup.queue_number <= 1000 do %>
                <div class="text-xs text-emerald-400 mt-1">← You're here!</div>
              <% end %>
            </div>
          </div>
          
          <!-- Public -->
          <div class={"flex gap-3 " <> if(@signup.queue_number > 1000, do: "opacity-100", else: "opacity-50")}>
            <div class="text-2xl">🌍</div>
            <div>
              <div class="font-medium text-white">Public <span class="text-slate-400">#1001+</span></div>
              <div class="text-sm text-slate-400">General access in batches: 500, then 1000, then 2000 at a time</div>
              <%= if @signup.queue_number > 1000 do %>
                <div class="text-xs text-slate-300 mt-1">← You're here!</div>
              <% end %>
            </div>
          </div>
        </div>
      </div>
      
      <!-- Status Link -->
      <div class="bg-slate-800/30 rounded-xl p-4 mb-6">
        <p class="text-slate-400 text-sm mb-2">Bookmark your status page:</p>
        <a 
          href={"/waitlist/status/#{@signup.status_token}"} 
          class="block text-sm text-cyan-400 hover:text-cyan-300 bg-slate-900 px-4 py-3 rounded-lg break-all transition"
        >
          https://stream.onelist.my/waitlist/status/<%= @signup.status_token %>
        </a>
      </div>
      
      <p class="text-slate-400 text-sm">
        We'll email <span class="text-white"><%= @signup.email %></span> when it's your turn.
      </p>
    </div>
    """
  end

  defp signup_form(assigns) do
    ~H"""
    <div class="text-center mb-12">
      <h1 class="text-4xl sm:text-5xl font-bold text-white mb-4">
        Join Onelist
      </h1>
      
      <!-- Live number display -->
      <div class="mb-6">
        <div class="inline-flex items-center gap-3 bg-slate-800/50 rounded-2xl px-6 py-4 border border-slate-700">
          <span class="text-3xl"><%= @tier_info.emoji %></span>
          <div class="text-left">
            <div class="text-slate-400 text-sm">You'll be</div>
            <div class={"text-3xl font-bold bg-gradient-to-r #{@tier_info.badge_class} bg-clip-text text-transparent"}>
              #<%= @next_number %>
            </div>
          </div>
          <div class="text-left border-l border-slate-600 pl-3 ml-2">
            <div class="text-white font-semibold"><%= @tier_info.name %></div>
            <div class="text-slate-400 text-sm"><%= @tier_info.description %></div>
          </div>
        </div>
      </div>
      
      <!-- Tier progress -->
      <%= if @tier_info.spots_remaining do %>
        <p class={"font-medium " <> if(@next_number <= 100, do: "text-cyan-400", else: "text-emerald-400")}>
          <span class="text-xl"><%= @tier_info.spots_remaining %></span> 
          <%= @tier_info.name %> spots remaining
        </p>
      <% end %>
    </div>
    
    <div class="bg-slate-800/50 rounded-2xl p-8 border border-slate-700">
      <.form for={@form} phx-change="validate" phx-submit="submit" class="space-y-6">
        
        <div>
          <label for="signup_email" class="block text-sm font-medium text-slate-300 mb-2">
            Email *
          </label>
          <.input 
            field={@form[:email]} 
            type="email" 
            placeholder="you@example.com"
            class="w-full px-4 py-3 bg-slate-900 border border-slate-600 rounded-lg text-white placeholder-slate-500 focus:border-cyan-500 focus:ring-1 focus:ring-cyan-500"
            required
          />
        </div>
        
        <div>
          <label for="signup_name" class="block text-sm font-medium text-slate-300 mb-2">
            Name <span class="text-slate-500">(optional)</span>
          </label>
          <.input 
            field={@form[:name]} 
            type="text" 
            placeholder="What should we call you?"
            class="w-full px-4 py-3 bg-slate-900 border border-slate-600 rounded-lg text-white placeholder-slate-500 focus:border-cyan-500 focus:ring-1 focus:ring-cyan-500"
          />
        </div>
        
        <div>
          <label for="signup_reason" class="block text-sm font-medium text-slate-300 mb-2">
            Why Onelist? <span class="text-slate-500">(optional)</span>
          </label>
          <textarea 
            name="signup[reason]"
            id="signup_reason"
            rows="3"
            placeholder="What are you hoping to remember?"
            class="w-full px-4 py-3 bg-slate-900 border border-slate-600 rounded-lg text-white placeholder-slate-500 focus:border-cyan-500 focus:ring-1 focus:ring-cyan-500 resize-none"
          ><%= @form[:reason].value %></textarea>
        </div>
        
        <div>
          <label for="signup_referral_source" class="block text-sm font-medium text-slate-300 mb-2">
            How did you hear about us? <span class="text-slate-500">(optional)</span>
          </label>
          <.input 
            field={@form[:referral_source]} 
            type="text" 
            placeholder="Twitter, friend, blog post..."
            class="w-full px-4 py-3 bg-slate-900 border border-slate-600 rounded-lg text-white placeholder-slate-500 focus:border-cyan-500 focus:ring-1 focus:ring-cyan-500"
          />
        </div>
        
        <button 
          type="submit"
          class="w-full py-4 px-6 bg-gradient-to-r from-cyan-500 to-blue-500 hover:from-cyan-400 hover:to-blue-400 text-white font-semibold rounded-lg transition-all transform hover:scale-[1.02] active:scale-[0.98]"
        >
          Join the Headwaters 🌊
        </button>
        
      </.form>
    </div>
    
    <!-- Self-Hosted First Philosophy -->
    <div class="mt-10 bg-slate-800/30 rounded-2xl p-6 border border-slate-700">
      <h3 class="text-lg font-semibold text-white mb-4 flex items-center gap-2">
        <span>💻</span> Your Data, Your Machine, Forever
      </h3>
      
      <div class="space-y-4 text-slate-300 text-sm">
        <p>
          Onelist is <span class="text-white font-medium">self-hosted first</span> — 
          run it on your own hardware, keep your memories under your control, no subscription required.
        </p>
        
        <div class="grid gap-3">
          <div class="flex gap-3 items-start">
            <span class="text-cyan-400 mt-0.5">→</span>
            <div>
              <span class="text-white font-medium">Fully independent</span> — 
              Complete Onelist on your machine, works forever without us
            </div>
          </div>
          
          <div class="flex gap-3 items-start">
            <span class="text-cyan-400 mt-0.5">→</span>
            <div>
              <span class="text-white font-medium">Cloud optional</span> — 
              Want sync across devices? Connect when you're ready. Or don't.
            </div>
          </div>
          
          <div class="flex gap-3 items-start">
            <span class="text-cyan-400 mt-0.5">→</span>
            <div>
              <span class="text-white font-medium">True ownership</span> — 
              Your memories aren't hostage to our servers or business model
            </div>
          </div>
        </div>
        
        <p class="text-slate-400 pt-2">
          Cloud adds convenience — sync, backup, mobile access. But local is complete.
        </p>
      </div>
    </div>
    
    <p class="text-center text-slate-500 text-sm mt-6">
      No spam, ever. We'll only email you about your spot.
    </p>
    """
  end
end
