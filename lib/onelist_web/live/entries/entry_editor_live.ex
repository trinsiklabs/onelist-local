defmodule OnelistWeb.Entries.EntryEditorLive do
  use OnelistWeb, :live_view

  alias Onelist.Entries
  alias Onelist.Entries.Entry
  alias Onelist.Tags
  alias OnelistWeb.Entries.Components.PublicToggleComponent

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       entry: nil,
       changeset: nil,
       content: "",
       tags: [],
       available_tags: [],
       saving: false
     )}
  end

  @impl true
  def handle_params(%{"id" => id}, _url, socket) do
    user = socket.assigns.current_user
    entry = Entries.get_user_entry(user, id)

    if entry do
      representation = Entries.get_primary_representation(entry)
      content = if representation, do: representation.content || "", else: ""
      tags = Tags.list_entry_tags(entry)
      available_tags = Tags.list_user_tags(user)

      {:noreply,
       assign(socket,
         page_title: "Edit Entry",
         entry: entry,
         changeset: Entry.update_changeset(entry, %{}),
         content: content,
         tags: tags,
         available_tags: available_tags,
         action: :edit
       )}
    else
      {:noreply,
       socket
       |> put_flash(:error, "Entry not found")
       |> push_navigate(to: ~p"/app/entries")}
    end
  end

  @impl true
  def handle_params(_params, _url, socket) do
    user = socket.assigns.current_user
    available_tags = Tags.list_user_tags(user)

    {:noreply,
     assign(socket,
       page_title: "New Entry",
       entry: %Entry{entry_type: "note"},
       changeset: Entry.changeset(%Entry{}, %{entry_type: "note"}),
       content: "",
       tags: [],
       available_tags: available_tags,
       action: :new
     )}
  end

  @impl true
  def handle_event("validate", %{"entry" => entry_params}, socket) do
    changeset =
      socket.assigns.entry
      |> Entry.changeset(entry_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, changeset: changeset)}
  end

  @impl true
  def handle_event("save", %{"entry" => entry_params}, socket) do
    content = Map.get(entry_params, "content", socket.assigns.content)

    case socket.assigns.action do
      :new -> create_entry(socket, entry_params, content)
      :edit -> update_entry(socket, entry_params, content)
    end
  end

  @impl true
  def handle_event("update_content", %{"content" => content}, socket) do
    {:noreply, assign(socket, content: content)}
  end

  @impl true
  def handle_event("add_tag", %{"tag_id" => tag_id}, socket) do
    tag = Enum.find(socket.assigns.available_tags, &(&1.id == tag_id))

    if tag && socket.assigns.entry.id do
      {:ok, _} = Tags.add_tag_to_entry(socket.assigns.entry, tag)
      tags = Tags.list_entry_tags(socket.assigns.entry)
      {:noreply, assign(socket, tags: tags)}
    else
      # For new entries, just add to local state
      if tag do
        tags = [tag | socket.assigns.tags] |> Enum.uniq_by(& &1.id)
        {:noreply, assign(socket, tags: tags)}
      else
        {:noreply, socket}
      end
    end
  end

  @impl true
  def handle_event("remove_tag", %{"tag_id" => tag_id}, socket) do
    tag = Enum.find(socket.assigns.tags, &(&1.id == tag_id))

    if tag && socket.assigns.entry.id do
      {:ok, _} = Tags.remove_tag_from_entry(socket.assigns.entry, tag)
      tags = Tags.list_entry_tags(socket.assigns.entry)
      {:noreply, assign(socket, tags: tags)}
    else
      if tag do
        tags = Enum.reject(socket.assigns.tags, &(&1.id == tag_id))
        {:noreply, assign(socket, tags: tags)}
      else
        {:noreply, socket}
      end
    end
  end

  @impl true
  def handle_info({:entry_updated, updated_entry}, socket) do
    {:noreply, assign(socket, entry: updated_entry)}
  end

  @impl true
  def handle_info({:flash, kind, message}, socket) do
    {:noreply, put_flash(socket, kind, message)}
  end

  defp create_entry(socket, entry_params, content) do
    user = socket.assigns.current_user
    entry_params = Map.put(entry_params, "entry_type", entry_params["entry_type"] || "note")

    case Entries.create_entry(user, entry_params) do
      {:ok, entry} ->
        # Add representation if content provided
        if content && content != "" do
          Entries.add_representation(entry, %{type: "markdown", content: content})
        end

        # Add tags
        Enum.each(socket.assigns.tags, fn tag ->
          Tags.add_tag_to_entry(entry, tag)
        end)

        {:noreply,
         socket
         |> put_flash(:info, "Entry created successfully")
         |> push_navigate(to: ~p"/app/entries")}

      {:error, changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  defp update_entry(socket, entry_params, content) do
    entry = socket.assigns.entry

    case Entries.update_entry(entry, entry_params) do
      {:ok, _updated_entry} ->
        # Update or create representation
        representation = Entries.get_primary_representation(entry)

        if representation do
          Entries.update_representation(representation, %{content: content})
        else
          if content && content != "" do
            Entries.add_representation(entry, %{type: "markdown", content: content})
          end
        end

        {:noreply,
         socket
         |> put_flash(:info, "Entry updated successfully")
         |> push_navigate(to: ~p"/app/entries")}

      {:error, changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8 max-w-4xl">
      <div class="mb-6">
        <.link navigate={~p"/app/entries"} class="text-indigo-600 hover:text-indigo-800">
          &larr; Back to Entries
        </.link>
      </div>

      <h1 class="text-2xl font-bold text-gray-900 mb-6">
        <%= if @action == :new, do: "New Entry", else: "Edit Entry" %>
      </h1>

      <.form
        for={@changeset}
        id="entry-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-6"
      >
        <div>
          <label for="entry_title" class="block text-sm font-medium text-gray-700">Title</label>
          <input
            type="text"
            name="entry[title]"
            id="entry_title"
            value={@changeset.changes[:title] || @entry.title}
            class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
            placeholder="Entry title (optional)"
          />
        </div>

        <div>
          <label for="entry_type" class="block text-sm font-medium text-gray-700">Type</label>
          <select
            name="entry[entry_type]"
            id="entry_type"
            class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
          >
            <%= for type <- ~w(note memory photo video) do %>
              <option
                value={type}
                selected={(@changeset.changes[:entry_type] || @entry.entry_type) == type}
              >
                <%= String.capitalize(type) %>
              </option>
            <% end %>
          </select>
        </div>

        <div>
          <label for="entry_content" class="block text-sm font-medium text-gray-700 mb-1">
            Content
          </label>
          <!-- Hidden input for form submission -->
          <input type="hidden" name="entry[content]" id="entry-content-input" value={@content} />
          <!-- Toast UI Editor container -->
          <div
            id="markdown-editor"
            phx-hook="Editor"
            phx-update="ignore"
            data-content={@content}
            class="border border-gray-300 rounded-md overflow-hidden"
          >
          </div>
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">Tags</label>
          <div class="flex flex-wrap gap-2 mb-2">
            <%= for tag <- @tags do %>
              <span class="inline-flex items-center px-2 py-1 rounded-full text-sm bg-indigo-100 text-indigo-800">
                <%= tag.name %>
                <button
                  type="button"
                  phx-click="remove_tag"
                  phx-value-tag_id={tag.id}
                  class="ml-1 text-indigo-600 hover:text-indigo-800"
                >
                  &times;
                </button>
              </span>
            <% end %>
          </div>

          <%= if Enum.any?(@available_tags -- @tags) do %>
            <select
              phx-change="add_tag"
              name="tag_id"
              class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
            >
              <option value="">Add a tag...</option>
              <%= for tag <- @available_tags -- @tags do %>
                <option value={tag.id}><%= tag.name %></option>
              <% end %>
            </select>
          <% end %>
        </div>

        <%= if @action == :edit and @entry.id do %>
          <div class="flex items-center gap-4">
            <.live_component
              module={PublicToggleComponent}
              id="entry-public-toggle"
              entry={@entry}
              user={@current_user}
            />
          </div>
        <% else %>
          <div class="flex items-center gap-4">
            <label class="flex items-center">
              <input
                type="checkbox"
                name="entry[public]"
                value="true"
                checked={@changeset.changes[:public] || @entry.public}
                class="rounded border-gray-300 text-indigo-600 focus:ring-indigo-500"
                data-testid="public-toggle"
              />
              <span class="ml-2 text-sm text-gray-700">Make public (requires username)</span>
            </label>
          </div>
        <% end %>

        <div class="flex justify-end gap-4">
          <.link navigate={~p"/app/entries"} class="px-4 py-2 text-gray-700 hover:text-gray-900">
            Cancel
          </.link>
          <button
            type="submit"
            class="bg-indigo-600 text-white px-4 py-2 rounded-md hover:bg-indigo-700 disabled:opacity-50"
            disabled={@saving}
          >
            <%= if @action == :new, do: "Create Entry", else: "Save Changes" %>
          </button>
        </div>
      </.form>
    </div>
    """
  end
end
