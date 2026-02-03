ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Onelist.Repo, :manual)

# Load support files
Code.require_file("support/data_case.ex", __DIR__)
