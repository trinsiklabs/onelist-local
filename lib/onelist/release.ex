defmodule Onelist.Release do
  @moduledoc """
  Release tasks for production deployment.

  Run migrations:
      bin/onelist eval "Onelist.Release.migrate()"

  Rollback:
      bin/onelist eval "Onelist.Release.rollback(Onelist.Repo, 20231201000000)"

  Setup initial user (local mode):
      bin/onelist eval "Onelist.Release.setup_initial_user()"
  """

  @app :onelist

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def create_extensions do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          repo.query("CREATE EXTENSION IF NOT EXISTS vector", [])
          repo.query("CREATE EXTENSION IF NOT EXISTS pg_trgm", [])
        end)
    end
  end

  @doc """
  Creates the initial user for local mode from INITIAL_USER_EMAIL env var.
  Generates a random password and prints it to stdout.
  """
  def setup_initial_user do
    load_app()
    
    email = System.get_env("INITIAL_USER_EMAIL")
    
    if is_nil(email) or email == "" do
      IO.puts("⚠️  INITIAL_USER_EMAIL not set, skipping user creation")
      :skip
    else
      {:ok, _, _} = Ecto.Migrator.with_repo(Onelist.Repo, fn _repo ->
        case Onelist.Accounts.get_user_by_email(email) do
          nil ->
            # Generate random password
            password = :crypto.strong_rand_bytes(16) |> Base.url_encode64() |> binary_part(0, 16)
            
            case Onelist.Accounts.register_user(%{
              email: email,
              password: password,
              password_confirmation: password
            }) do
              {:ok, user} ->
                IO.puts("")
                IO.puts("✅ Initial user created!")
                IO.puts("   Email: #{user.email}")
                IO.puts("   Password: #{password}")
                IO.puts("")
                IO.puts("   ⚠️  Save this password - it won't be shown again!")
                IO.puts("")
                {:ok, user}
              
              {:error, changeset} ->
                IO.puts("❌ Failed to create user: #{inspect(changeset.errors)}")
                {:error, changeset}
            end
          
          _existing ->
            IO.puts("ℹ️  User #{email} already exists")
            :exists
        end
      end)
    end
  end

  @doc """
  Full setup for local mode: migrate + extensions + initial user
  """
  def setup_local do
    IO.puts("🌊 Setting up Onelist Local...")
    IO.puts("")
    
    IO.puts("📦 Creating extensions...")
    create_extensions()
    
    IO.puts("🔄 Running migrations...")
    migrate()
    
    IO.puts("👤 Setting up initial user...")
    setup_initial_user()
    
    IO.puts("")
    IO.puts("✅ Setup complete!")
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
