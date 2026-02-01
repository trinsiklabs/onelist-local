defmodule Onelist.Waitlist do
  @moduledoc """
  The Waitlist context for managing Headwaters early access signups.
  
  Headwaters are the first 100 users — where the river begins.
  """

  import Ecto.Query
  alias Onelist.Repo
  alias Onelist.Waitlist.Signup

  @max_headwaters 100

  @doc """
  Returns the maximum number of Headwaters spots.
  """
  def max_headwaters, do: @max_headwaters

  @doc """
  Returns the current count of signups.
  """
  def count_signups do
    Repo.aggregate(Signup, :count)
  end

  @doc """
  Returns the number of remaining spots.
  """
  def remaining_spots do
    max(@max_headwaters - count_signups(), 0)
  end

  @doc """
  Returns true if there are spots available.
  """
  def spots_available? do
    remaining_spots() > 0
  end

  @doc """
  Gets a signup by email.
  """
  def get_signup_by_email(email) do
    Repo.get_by(Signup, email: String.downcase(email))
  end

  @doc """
  Gets a signup by status token.
  """
  def get_signup_by_token(token) do
    Repo.get_by(Signup, status_token: token)
  end

  @doc """
  Gets a signup by queue number.
  """
  def get_signup_by_queue_number(number) do
    Repo.get_by(Signup, queue_number: number)
  end

  @doc """
  Creates a new waitlist signup.
  
  Returns {:ok, signup} or {:error, changeset} or {:error, :waitlist_full}
  """
  def create_signup(attrs) do
    if spots_available?() do
      # Get next queue number atomically
      next_number = get_next_queue_number()
      
      # Normalize to string keys and add generated fields
      email = attrs[:email] || attrs["email"] || ""
      attrs = %{
        "email" => String.downcase(email),
        "name" => attrs[:name] || attrs["name"],
        "reason" => attrs[:reason] || attrs["reason"],
        "referral_source" => attrs[:referral_source] || attrs["referral_source"],
        "queue_number" => next_number,
        "status_token" => generate_token()
      }
      
      result = 
        %Signup{}
        |> Signup.changeset(attrs)
        |> Repo.insert()
      
      case result do
        {:ok, signup} ->
          # Broadcast the new signup count
          broadcast_signup_update()
          {:ok, signup}
        error ->
          error
      end
    else
      {:error, :waitlist_full}
    end
  end

  @doc """
  Subscribe to waitlist updates.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Onelist.PubSub, "waitlist:updates")
  end

  defp broadcast_signup_update do
    Phoenix.PubSub.broadcast(
      Onelist.PubSub,
      "waitlist:updates",
      {:waitlist_updated, %{remaining: remaining_spots(), total: count_signups()}}
    )
  end

  @doc """
  Checks if an email is already on the waitlist.
  """
  def email_registered?(email) do
    query = from s in Signup, where: s.email == ^String.downcase(email)
    Repo.exists?(query)
  end

  @doc """
  Gets the position info for a signup (for display).
  """
  def get_position_info(%Signup{} = signup) do
    total = count_signups()
    activated_count = count_by_status("activated")
    invited_count = count_by_status("invited")
    
    # How many people are ahead in the queue
    ahead_in_queue = signup.queue_number - 1 - activated_count - invited_count
    ahead_in_queue = max(ahead_in_queue, 0)
    
    %{
      queue_number: signup.queue_number,
      total_signups: total,
      max_spots: @max_headwaters,
      spots_remaining: remaining_spots(),
      status: signup.status,
      ahead_in_queue: ahead_in_queue,
      activated_count: activated_count,
      invited_count: invited_count,
      estimated_wait: estimate_wait(ahead_in_queue),
      signed_up_at: signup.inserted_at
    }
  end

  @doc """
  Lists all signups, ordered by queue number.
  """
  def list_signups(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    status = Keyword.get(opts, :status)
    
    query = from s in Signup, order_by: [asc: s.queue_number], limit: ^limit
    
    query = if status do
      from s in query, where: s.status == ^status
    else
      query
    end
    
    Repo.all(query)
  end

  @doc """
  Invites a signup (sends them access).
  """
  def invite_signup(%Signup{} = signup) do
    signup
    |> Signup.invite_changeset()
    |> Repo.update()
  end

  @doc """
  Marks a signup as activated (they've created an account).
  """
  def activate_signup(%Signup{} = signup, user_id) do
    signup
    |> Signup.activate_changeset(user_id)
    |> Repo.update()
  end

  @doc """
  Gets the next signup to invite (lowest queue number that's still waiting).
  """
  def next_to_invite do
    query = from s in Signup,
      where: s.status == "waiting",
      order_by: [asc: s.queue_number],
      limit: 1
    
    Repo.one(query)
  end

  # Private functions

  defp get_next_queue_number do
    case Repo.one(from s in Signup, select: max(s.queue_number)) do
      nil -> 1
      max -> max + 1
    end
  end

  defp generate_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  defp count_by_status(status) do
    query = from s in Signup, where: s.status == ^status
    Repo.aggregate(query, :count)
  end

  defp estimate_wait(ahead_in_queue) do
    # Rough estimate: assume we activate ~5 users per week initially
    # This should be configurable/dynamic later
    users_per_week = 5
    
    weeks = ceil(ahead_in_queue / users_per_week)
    
    cond do
      ahead_in_queue == 0 -> "You're next!"
      weeks <= 1 -> "Less than a week"
      weeks <= 2 -> "1-2 weeks"
      weeks <= 4 -> "2-4 weeks"
      weeks <= 8 -> "1-2 months"
      true -> "2+ months"
    end
  end
end
