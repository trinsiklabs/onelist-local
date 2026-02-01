defmodule Onelist.Repo do
  use Ecto.Repo,
    otp_app: :onelist,
    adapter: Ecto.Adapters.Postgres

  @impl true
  def init(_type, config) do
    {:ok, Keyword.put(config, :types, Onelist.PostgresTypes)}
  end
end
