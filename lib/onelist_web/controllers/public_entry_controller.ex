defmodule OnelistWeb.PublicEntryController do
  @moduledoc """
  Controller for serving public entries at /:username/:public_id.
  """
  use OnelistWeb, :controller

  alias Onelist.Entries

  @doc """
  Shows a public entry as HTML.
  """
  def show(conn, %{"username" => username, "public_id" => public_id}) do
    case Entries.get_public_entry(username, public_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> put_view(html: OnelistWeb.ErrorHTML)
        |> render("404.html")

      entry ->
        # Get the html_public representation for display
        entry = Onelist.Repo.preload(entry, :assets)
        html_content = get_html_content(entry)
        description = get_description(entry)
        public_url = Entries.public_entry_url(entry)

        conn
        |> put_resp_header("cache-control", "public, max-age=3600")
        |> render(:show,
          entry: entry,
          user: entry.user,
          html_content: html_content,
          assets: entry.assets || [],
          page_title: entry.title || "Untitled Entry",
          meta_description: description,
          og_title: entry.title || "Untitled Entry",
          og_type: "article",
          og_url: public_url,
          og_description: description
        )
    end
  end

  defp get_html_content(entry) do
    entry = Onelist.Repo.preload(entry, :representations)

    # First try to get html_public representation
    html_public = Enum.find(entry.representations, &(&1.type == "html_public"))

    if html_public do
      html_public.content
    else
      # Fall back to primary representation (markdown)
      case Entries.get_primary_representation(entry) do
        nil -> "<p>No content</p>"
        rep -> simple_markdown_to_html(rep.content || "")
      end
    end
  end

  defp simple_markdown_to_html(markdown) when is_binary(markdown) do
    # Simple markdown to HTML conversion for fallback
    html =
      markdown
      |> String.replace(~r/^### (.+)$/m, "<h3>\\1</h3>")
      |> String.replace(~r/^## (.+)$/m, "<h2>\\1</h2>")
      |> String.replace(~r/^# (.+)$/m, "<h1>\\1</h1>")
      |> String.replace(~r/\*\*(.+?)\*\*/, "<strong>\\1</strong>")
      |> String.replace(~r/\*(.+?)\*/, "<em>\\1</em>")
      |> String.replace(~r/\n\n/, "</p><p>")
      # Sanitize script tags
      |> String.replace(~r/<script[^>]*>.*?<\/script>/is, "")
      |> String.replace(~r/<script[^>]*>/i, "")
      |> String.replace(~r/<\/script>/i, "")

    ~s(<article class="prose prose-lg mx-auto"><p>#{html}</p></article>)
  end

  defp get_description(entry) do
    entry = Onelist.Repo.preload(entry, :representations)

    content =
      case Entries.get_primary_representation(entry) do
        nil -> ""
        rep -> rep.content || ""
      end

    # Strip markdown formatting and get first 160 chars
    content
    |> String.replace(~r/^#+\s*/, "")
    |> String.replace(~r/\*+/, "")
    |> String.replace(~r/\n+/, " ")
    |> String.trim()
    |> String.slice(0, 160)
    |> Kernel.<>("...")
  end
end
