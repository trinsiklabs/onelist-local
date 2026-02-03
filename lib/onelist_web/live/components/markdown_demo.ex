defmodule OnelistWeb.MarkdownDemo do
  use OnelistWeb, :live_component

  @default_content """
  # Welcome to Onelist

  Try writing some markdown here:

  - Lists
  - **Bold text**
  - *Italic text*
  - [Links](https://example.com)
  """

  @impl true
  def mount(socket) do
    case render_markdown(@default_content) do
      {:ok, html} ->
        {:ok,
         socket
         |> assign(:content, @default_content)
         |> assign(:preview_html, html)
         |> assign(:error, nil)
         |> assign(:is_debouncing, false)
         |> assign(:show_syntax_help, false)}

      {:error, message} ->
        {:ok,
         socket
         |> assign(:content, @default_content)
         |> assign(:preview_html, "")
         |> assign(:error, message)
         |> assign(:is_debouncing, false)
         |> assign(:show_syntax_help, false)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-full p-4 bg-white rounded-lg shadow-sm">
      <div class="flex flex-col sm:flex-col md:flex-row gap-4">
        <!-- Editor Section -->
        <div class="flex-1">
          <div class="flex justify-between items-center mb-2">
            <h3 class="text-lg font-semibold">Try Markdown</h3>
            <button
              type="button"
              class="text-sm text-blue-600 hover:text-blue-800"
              data-test-id="syntax-help-button"
              aria-label="Toggle markdown syntax help"
              phx-click="toggle_syntax_help"
              phx-target={@myself}
            >
              Need help?
            </button>
          </div>
          <textarea
            id="markdown-input"
            data-test-id="markdown-input"
            class="w-full h-64 p-3 border rounded-md font-mono text-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500 sm:text-sm sm:min-h-[100px]"
            aria-label="Markdown editor"
            touch-action="manipulation"
            phx-debounce="100"
            phx-change="update_preview"
            phx-target={@myself}
          ><%= @content %></textarea>
        </div>
        <!-- Preview Section -->
        <div class="flex-1">
          <h3 class="text-lg font-semibold mb-2">Preview</h3>
          <div
            id="markdown-preview"
            data-test-id="markdown-preview"
            class="prose max-w-none p-3 border rounded-md min-h-[16rem] sm:min-h-[100px]"
            aria-label="Preview pane"
            aria-live="polite"
          >
            <%= if @error do %>
              <div data-test-id="preview-error" class="text-red-500">
                <%= @error %>
              </div>
            <% else %>
              <%= Phoenix.HTML.raw(@preview_html) %>
            <% end %>
            <div class="sr-only">Preview updated</div>
          </div>
        </div>
      </div>
      <!-- Syntax Help Panel -->
      <%= if @show_syntax_help do %>
        <div class="mt-4 p-4 bg-gray-50 rounded-lg" data-test-id="syntax-help">
          <h4 class="text-lg font-semibold mb-2">Markdown Syntax Guide</h4>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <h5 class="font-medium mb-2">Basic Formatting</h5>
              <div class="relative">
                <pre class="text-sm bg-white p-2 rounded"><code data-test-id="syntax-example"># Heading 1
                  ## Heading 2
                  **Bold text**
                  *Italic text*
                  [Link](https://example.com)</code></pre>
                <button
                  type="button"
                  class="absolute top-2 right-2 text-sm text-gray-500 hover:text-gray-700"
                  data-test-id="copy-button"
                  phx-click="copy_example"
                  phx-value-example="basic"
                  phx-target={@myself}
                >
                  Copy example
                </button>
              </div>
            </div>
            <div>
              <h5 class="font-medium mb-2">Lists and Quotes</h5>
              <div class="relative">
                <pre class="text-sm bg-white p-2 rounded"><code data-test-id="lists-example">{[
                  "- Bullet point",
                  "1. Numbered list",
                  "> Blockquote",
                  "```",
                  "Code block",
                  "```"
                ] |> Enum.join("\n")}</code></pre>
                <button
                  type="button"
                  class="absolute top-2 right-2 text-sm text-gray-500 hover:text-gray-700"
                  data-test-id="copy-button"
                  phx-click="copy_example"
                  phx-value-example="lists"
                  phx-target={@myself}
                >
                  Copy example
                </button>
              </div>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def handle_event("update_preview", %{"value" => content}, socket) do
    case render_markdown(content) do
      {:ok, html} ->
        {:noreply,
         socket
         |> assign(:content, content)
         |> assign(:preview_html, html)
         |> assign(:error, nil)}

      {:error, message} ->
        {:noreply,
         socket
         |> assign(:content, content)
         |> assign(:preview_html, "")
         |> assign(:error, message)}
    end
  end

  @impl true
  def handle_event("toggle_syntax_help", _, socket) do
    {:noreply, assign(socket, :show_syntax_help, !socket.assigns.show_syntax_help)}
  end

  @impl true
  def handle_event("copy_example", %{"example" => example}, socket) do
    text =
      case example do
        "basic" ->
          """
          # Heading 1
          ## Heading 2
          **Bold text**
          *Italic text*
          [Link](https://example.com)
          """

        "lists" ->
          """
          - Bullet point
          1. Numbered list
          > Blockquote
          ```
          Code block
          ```
          """
      end

    {:noreply, push_event(socket, "clipboard", %{text: text})}
  end

  defp render_markdown(content) do
    try do
      case Earmark.as_html(content, compact_output: true) do
        {:ok, html, _} ->
          html =
            if String.contains?(content, "<script>") do
              content
              |> Phoenix.HTML.html_escape()
              |> Phoenix.HTML.safe_to_string()
            else
              html
            end

          {:ok, html}

        {:error, _, message} ->
          {:error, "Could not parse markdown: #{message}"}
      end
    rescue
      e in _ -> {:error, "Could not parse markdown: #{Exception.message(e)}"}
    end
  end
end
