defmodule OnelistWeb.Plugs.TrustedMemoryGuard do
  @moduledoc """
  Plug that guards API endpoints for trusted memory accounts.

  Blocks PUT, PATCH, and DELETE requests on entry resources
  for users with trusted_memory_mode enabled.
  """

  import Plug.Conn
  alias Onelist.TrustedMemory

  def init(opts), do: opts

  def call(conn, _opts) do
    user = conn.assigns[:current_user]
    method = conn.method

    if should_block?(user, method, conn.path_info) do
      # Log the attempt
      entry_id = extract_entry_id(conn.path_info)

      if entry_id && user do
        TrustedMemory.log_operation(
          user.id,
          entry_id,
          action_from_method(method),
          "denied",
          %{
            reason: "Trusted memory mode prevents mutations via API",
            path: conn.request_path,
            method: method
          }
        )
      end

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        403,
        Jason.encode!(%{
          error: "immutable_memory",
          message: "This account uses trusted memory. Entries cannot be modified or deleted.",
          code: "TRUSTED_MEMORY_IMMUTABLE",
          suggestion:
            "Create a new entry instead, or contact your administrator for rollback options."
        })
      )
      |> halt()
    else
      conn
    end
  end

  defp should_block?(nil, _method, _path), do: false

  defp should_block?(user, method, path) do
    TrustedMemory.enabled?(user) &&
      method in ["PUT", "PATCH", "DELETE"] &&
      is_entry_path?(path)
  end

  defp is_entry_path?(["api", "v1", "entries" | _]), do: true
  defp is_entry_path?(["api", "v1", "memory" | _]), do: true
  defp is_entry_path?(_), do: false

  defp extract_entry_id(["api", "v1", "entries", id | _]) when byte_size(id) == 36, do: id
  defp extract_entry_id(["api", "v1", "memory", id | _]) when byte_size(id) == 36, do: id
  defp extract_entry_id(_), do: nil

  defp action_from_method("PUT"), do: "attempted_edit"
  defp action_from_method("PATCH"), do: "attempted_edit"
  defp action_from_method("DELETE"), do: "attempted_delete"
  defp action_from_method(_), do: "unknown"
end
