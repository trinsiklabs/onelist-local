defmodule Mix.Tasks.Onelist.SetPassword do
  @moduledoc """
  Set a password for a user by username.

  ## Usage

      mix onelist.set_password USERNAME PASSWORD

  ## Examples

      mix onelist.set_password cynthia MySecurePassword123

  The password must meet complexity requirements:
  - At least 10 characters
  - At least one lowercase letter
  - At least one uppercase letter
  - At least one digit

  PLAN-051: Phoenix Auth Migration
  """
  use Mix.Task

  @shortdoc "Set password for a user"

  @impl Mix.Task
  def run([username, password]) do
    # Start the application
    Mix.Task.run("app.start")

    alias Onelist.Repo
    alias Onelist.Accounts.User
    alias Onelist.Accounts.Password

    case Repo.get_by(User, username: username) do
      nil ->
        Mix.shell().error("User '#{username}' not found")
        System.halt(1)

      user ->
        # Hash the password
        hashed = Password.hash_password(password)

        # Update the user
        user
        |> Ecto.Changeset.change(%{hashed_password: hashed})
        |> Repo.update!()

        Mix.shell().info("Password set successfully for '#{username}'")
    end
  end

  def run(_) do
    Mix.shell().error("Usage: mix onelist.set_password USERNAME PASSWORD")
    System.halt(1)
  end
end
