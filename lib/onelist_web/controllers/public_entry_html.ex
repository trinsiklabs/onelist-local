defmodule OnelistWeb.PublicEntryHTML do
  @moduledoc """
  HTML views for public entry display.
  """
  use OnelistWeb, :html

  embed_templates "public_entry_html/*"

  @doc """
  Formats a datetime for display.
  """
  def format_date(nil), do: ""
  def format_date(%DateTime{} = dt) do
    Calendar.strftime(dt, "%B %d, %Y")
  end
  def format_date(%NaiveDateTime{} = dt) do
    Calendar.strftime(dt, "%B %d, %Y")
  end
end
