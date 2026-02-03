defmodule OnelistWeb.PageController do
  use OnelistWeb, :controller

  def home(conn, _params) do
    # The home page is often custom made,
    # so skip the default app layout.
    render(conn, :home, layout: false)
  end

  def roadmap_index(conn, _params) do
    serve_roadmap(conn)
  end

  def roadmap_index_html(conn, _params) do
    serve_roadmap(conn)
  end

  def roadmap_detail(conn, %{"slug" => slug}) do
    # Sanitize slug to prevent directory traversal
    safe_slug = slug |> String.replace(~r/[^a-zA-Z0-9_-]/, "")
    serve_roadmap_file(conn, "#{safe_slug}.html")
  end

  defp serve_roadmap(conn) do
    serve_roadmap_file(conn, "index.html")
  end

  defp serve_roadmap_file(conn, filename) do
    path = Application.app_dir(:onelist, "priv/static/roadmap/#{filename}")

    case File.read(path) do
      {:ok, content} ->
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(200, content)

      {:error, _} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(404, "Page not found")
    end
  end
end
