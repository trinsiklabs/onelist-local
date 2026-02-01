defmodule OnelistWeb.ErrorJSON do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on JSON requests.

  See config/config.exs.
  """

  # Renders a 400 Bad Request error.
  def render("400.json", %{message: message}) do
    %{errors: %{detail: message}}
  end

  def render("400.json", _assigns) do
    %{errors: %{detail: "Bad Request"}}
  end

  # Renders a 422 Unprocessable Entity error with changeset errors.
  def render("422.json", %{changeset: changeset}) do
    %{errors: format_changeset_errors(changeset)}
  end

  def render("422.json", %{message: message}) do
    %{errors: %{detail: message}}
  end

  def render("422.json", _assigns) do
    %{errors: %{detail: "Unprocessable Entity"}}
  end

  # By default, Phoenix returns the status message from
  # the template name. For example, "404.json" becomes
  # "Not Found".
  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
