defmodule Onelist.Usage do
  @moduledoc """
  Context for tracking and reporting API usage.
  """

  import Ecto.Query
  alias Onelist.Repo
  alias Onelist.Usage.ApiUsageLog

  @doc """
  Log API usage from a provider call.
  """
  def log_usage(attrs) do
    %ApiUsageLog{}
    |> ApiUsageLog.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Get usage summary for a time period.
  """
  def get_summary(opts \\ []) do
    since = Keyword.get(opts, :since, DateTime.add(DateTime.utc_now(), -24, :hour))
    provider = Keyword.get(opts, :provider)

    query = from l in ApiUsageLog,
      where: l.inserted_at >= ^since,
      group_by: l.provider,
      select: %{
        provider: l.provider,
        total_input_tokens: sum(l.input_tokens),
        total_output_tokens: sum(l.output_tokens),
        total_tokens: sum(l.total_tokens),
        total_cost_cents: sum(l.cost_cents),
        call_count: count(l.id)
      }

    query = if provider do
      from l in query, where: l.provider == ^provider
    else
      query
    end

    Repo.all(query)
  end

  @doc """
  Get usage summary for the last hour.
  """
  def get_hourly_summary do
    get_summary(since: DateTime.add(DateTime.utc_now(), -1, :hour))
  end

  @doc """
  Get usage summary for today (since midnight UTC).
  """
  def get_daily_summary do
    today = DateTime.utc_now() |> DateTime.to_date()
    {:ok, midnight} = NaiveDateTime.new(today, ~T[00:00:00])
    {:ok, since} = DateTime.from_naive(midnight, "Etc/UTC")
    get_summary(since: since)
  end

  @doc """
  Format usage summary as a human-readable string.
  """
  def format_summary(summaries) when is_list(summaries) do
    if Enum.empty?(summaries) do
      "No API usage recorded in this period."
    else
      summaries
      |> Enum.map(fn s ->
        cost = if s.total_cost_cents, do: Decimal.to_float(s.total_cost_cents) / 100, else: 0
        """
        #{String.upcase(s.provider)}:
          Calls: #{s.call_count}
          Tokens: #{s.total_tokens || 0} (in: #{s.total_input_tokens || 0}, out: #{s.total_output_tokens || 0})
          Est. Cost: $#{:erlang.float_to_binary(cost, decimals: 4)}
        """
      end)
      |> Enum.join("\n")
    end
  end
end
