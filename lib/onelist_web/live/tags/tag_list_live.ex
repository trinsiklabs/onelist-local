defmodule OnelistWeb.Tags.TagListLive do
  use OnelistWeb, :live_view

  alias Onelist.Tags
  alias Onelist.Tags.Tag

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns[:current_user] do
      tags_with_counts = Tags.list_user_tags_with_counts(socket.assigns.current_user)

      {:ok,
       assign(socket,
         page_title: "Tags",
         tags_with_counts: tags_with_counts,
         editing_tag_id: nil,
         new_tag_changeset: Tag.changeset(%Tag{}, %{})
       )}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_event("create_tag", %{"tag" => tag_params}, socket) do
    case Tags.create_tag(socket.assigns.current_user, tag_params) do
      {:ok, _tag} ->
        tags_with_counts = Tags.list_user_tags_with_counts(socket.assigns.current_user)

        {:noreply,
         assign(socket,
           tags_with_counts: tags_with_counts,
           new_tag_changeset: Tag.changeset(%Tag{}, %{})
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, new_tag_changeset: changeset)}
    end
  end

  @impl true
  def handle_event("edit_tag", %{"id" => id}, socket) do
    {:noreply, assign(socket, editing_tag_id: id)}
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing_tag_id: nil)}
  end

  @impl true
  def handle_event("update_tag", %{"id" => id, "tag" => tag_params}, socket) do
    tag = Tags.get_user_tag(socket.assigns.current_user, id)

    if tag do
      case Tags.update_tag(tag, tag_params) do
        {:ok, _tag} ->
          tags_with_counts = Tags.list_user_tags_with_counts(socket.assigns.current_user)

          {:noreply,
           assign(socket,
             tags_with_counts: tags_with_counts,
             editing_tag_id: nil
           )}

        {:error, _changeset} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete_tag", %{"id" => id}, socket) do
    tag = Tags.get_user_tag(socket.assigns.current_user, id)

    if tag do
      {:ok, _} = Tags.delete_tag(tag)
      tags_with_counts = Tags.list_user_tags_with_counts(socket.assigns.current_user)
      {:noreply, assign(socket, tags_with_counts: tags_with_counts)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8 max-w-2xl">
      <h1 class="text-2xl font-bold text-gray-900 mb-6">Tags</h1>

      <div class="bg-white rounded-lg shadow mb-6 p-4">
        <h2 class="text-lg font-medium text-gray-900 mb-4">New Tag</h2>
        <.form for={@new_tag_changeset} id="new-tag-form" phx-submit="create_tag" class="flex gap-2">
          <input
            type="text"
            name="tag[name]"
            placeholder="Tag name"
            class="flex-1 rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
            required
          />
          <button
            type="submit"
            class="bg-indigo-600 text-white px-4 py-2 rounded-md hover:bg-indigo-700"
          >
            Create
          </button>
        </.form>
      </div>

      <%= if Enum.empty?(@tags_with_counts) do %>
        <div class="text-center py-12 text-gray-500">
          <p class="text-lg">No tags yet</p>
          <p class="text-sm mt-2">Create your first tag to organize your entries.</p>
        </div>
      <% else %>
        <div class="bg-white rounded-lg shadow divide-y">
          <%= for {tag, count} <- @tags_with_counts do %>
            <div class="p-4 flex items-center justify-between">
              <%= if @editing_tag_id == tag.id do %>
                <.form
                  for={%{}}
                  id={"edit-tag-form-#{tag.id}"}
                  phx-submit="update_tag"
                  phx-value-id={tag.id}
                  class="flex-1 flex gap-2"
                >
                  <input
                    type="text"
                    name="tag[name]"
                    value={tag.name}
                    class="flex-1 rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                    required
                  />
                  <button
                    type="submit"
                    class="bg-indigo-600 text-white px-3 py-1 rounded-md hover:bg-indigo-700 text-sm"
                  >
                    Save
                  </button>
                  <button
                    type="button"
                    phx-click="cancel_edit"
                    class="text-gray-600 hover:text-gray-800 px-3 py-1 text-sm"
                  >
                    Cancel
                  </button>
                </.form>
              <% else %>
                <div class="flex-1">
                  <span class="font-medium text-gray-900"><%= tag.name %></span>
                  <span class="text-sm text-gray-500 ml-2">
                    <%= count %> <%= if count == 1, do: "entry", else: "entries" %>
                  </span>
                </div>
                <div class="flex gap-2">
                  <button
                    phx-click="edit_tag"
                    phx-value-id={tag.id}
                    class="text-indigo-600 hover:text-indigo-800"
                    data-test-id={"edit-tag-#{tag.id}"}
                  >
                    <svg
                      xmlns="http://www.w3.org/2000/svg"
                      class="h-5 w-5"
                      viewBox="0 0 20 20"
                      fill="currentColor"
                    >
                      <path d="M13.586 3.586a2 2 0 112.828 2.828l-.793.793-2.828-2.828.793-.793zM11.379 5.793L3 14.172V17h2.828l8.38-8.379-2.83-2.828z" />
                    </svg>
                  </button>
                  <button
                    phx-click="delete_tag"
                    phx-value-id={tag.id}
                    class="text-red-500 hover:text-red-700"
                    data-test-id={"delete-tag-#{tag.id}"}
                    data-confirm="Are you sure you want to delete this tag?"
                  >
                    <svg
                      xmlns="http://www.w3.org/2000/svg"
                      class="h-5 w-5"
                      viewBox="0 0 20 20"
                      fill="currentColor"
                    >
                      <path
                        fill-rule="evenodd"
                        d="M9 2a1 1 0 00-.894.553L7.382 4H4a1 1 0 000 2v10a2 2 0 002 2h8a2 2 0 002-2V6a1 1 0 100-2h-3.382l-.724-1.447A1 1 0 0011 2H9zM7 8a1 1 0 012 0v6a1 1 0 11-2 0V8zm5-1a1 1 0 00-1 1v6a1 1 0 102 0V8a1 1 0 00-1-1z"
                        clip-rule="evenodd"
                      />
                    </svg>
                  </button>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
