defmodule OnelistWeb.Api.V1.TrustedMemoryController do
  @moduledoc """
  API controller for trusted memory operations.

  Provides endpoints for:
  - Chain verification
  - Audit log access
  - Checkpoint/rollback management
  - Memory status
  """

  use OnelistWeb, :controller

  alias Onelist.TrustedMemory

  action_fallback OnelistWeb.FallbackController

  @doc """
  GET /api/v1/trusted-memory/status

  Returns the current trusted memory status for the authenticated user.
  """
  def status(conn, _params) do
    user = conn.assigns.current_user

    if TrustedMemory.enabled?(user) do
      status = TrustedMemory.get_status(user.id)
      json(conn, %{data: status})
    else
      conn
      |> put_status(:bad_request)
      |> json(%{
        error: "trusted_memory_not_enabled",
        message: "This account does not have trusted memory enabled."
      })
    end
  end

  @doc """
  GET /api/v1/trusted-memory/verify

  Verifies the integrity of the user's memory chain.
  """
  def verify(conn, _params) do
    user = conn.assigns.current_user

    if TrustedMemory.enabled?(user) do
      case TrustedMemory.verify_chain(user.id) do
        {:ok, :verified} ->
          TrustedMemory.log_operation(user.id, nil, "verify", "success")

          json(conn, %{
            verified: true,
            message: "Memory chain integrity verified."
          })

        {:ok, :empty_chain} ->
          json(conn, %{
            verified: true,
            message: "No chained entries yet."
          })

        {:error, :broken_chain, details} ->
          TrustedMemory.log_operation(user.id, details.entry_id, "verify", "failed", details)

          conn
          |> put_status(:conflict)
          |> json(%{
            verified: false,
            error: "chain_integrity_failed",
            message: "Memory chain integrity check failed.",
            details: details
          })
      end
    else
      conn
      |> put_status(:bad_request)
      |> json(%{error: "trusted_memory_not_enabled"})
    end
  end

  @doc """
  GET /api/v1/trusted-memory/audit-log

  Returns the audit log for the authenticated user.
  """
  def audit_log(conn, params) do
    user = conn.assigns.current_user
    limit = Map.get(params, "limit", "100") |> String.to_integer() |> min(1000)

    logs = TrustedMemory.get_audit_log(user.id, limit: limit)

    json(conn, %{
      data:
        Enum.map(logs, fn log ->
          %{
            id: log.id,
            action: log.action,
            actor: log.actor,
            outcome: log.outcome,
            entry_id: log.entry_id,
            details: log.details,
            timestamp: log.inserted_at
          }
        end)
    })
  end

  @doc """
  GET /api/v1/trusted-memory/checkpoints

  Lists checkpoints for the user.
  """
  def list_checkpoints(conn, params) do
    user = conn.assigns.current_user
    include_inactive = Map.get(params, "include_inactive", "false") == "true"

    checkpoints = TrustedMemory.list_checkpoints(user.id, include_inactive: include_inactive)

    json(conn, %{
      data: Enum.map(checkpoints, &checkpoint_to_json/1)
    })
  end

  @doc """
  POST /api/v1/trusted-memory/checkpoint

  Creates a rollback checkpoint. Requires human authorization.

  Body:
    - reason: string (optional)
    - after_sequence: integer (optional, defaults to latest)
    - authorization_token: string (required - proves human authorization)
  """
  def create_checkpoint(conn, params) do
    user = conn.assigns.current_user

    # In a real system, you'd verify the authorization_token
    # For now, we check for its presence as a simple gate
    unless Map.has_key?(params, "authorization_token") do
      conn
      |> put_status(:forbidden)
      |> json(%{
        error: "human_authorization_required",
        message: "Rollback checkpoints require human authorization. Include authorization_token."
      })
    else
      reason = Map.get(params, "reason", "API rollback request")
      after_sequence = Map.get(params, "after_sequence")

      result =
        if after_sequence do
          TrustedMemory.create_rollback_to(
            user.id,
            String.to_integer(after_sequence),
            authorized_by: "human",
            reason: reason
          )
        else
          TrustedMemory.create_rollback(user.id, authorized_by: "human", reason: reason)
        end

      case result do
        {:ok, checkpoint} ->
          conn
          |> put_status(:created)
          |> json(%{data: checkpoint_to_json(checkpoint)})

        {:error, :no_chained_entries} ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "no_chained_entries", message: "No chained entries to roll back."})

        {:error, changeset} when is_struct(changeset, Ecto.Changeset) ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "validation_failed", details: format_changeset_errors(changeset)})

        {:error, reason} ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: to_string(reason)})
      end
    end
  end

  @doc """
  DELETE /api/v1/trusted-memory/checkpoint/:id

  Recovers from a rollback by deactivating the checkpoint.
  Requires human authorization.
  """
  def delete_checkpoint(conn, %{"id" => _id} = params) do
    user = conn.assigns.current_user

    unless Map.has_key?(params, "authorization_token") do
      conn
      |> put_status(:forbidden)
      |> json(%{
        error: "human_authorization_required",
        message: "Recovery requires human authorization. Include authorization_token."
      })
    else
      case TrustedMemory.recover(user.id, authorized_by: "human") do
        {:ok, checkpoint} ->
          json(conn, %{
            data: checkpoint_to_json(checkpoint),
            message: "Checkpoint deactivated. All entries are now visible."
          })

        {:error, :no_active_checkpoint} ->
          conn
          |> put_status(:not_found)
          |> json(%{
            error: "no_active_checkpoint",
            message: "No active checkpoint to recover from."
          })

        {:error, reason} ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: to_string(reason)})
      end
    end
  end

  # ============================================
  # HELPERS
  # ============================================

  defp checkpoint_to_json(checkpoint) do
    %{
      id: checkpoint.id,
      type: checkpoint.checkpoint_type,
      after_sequence: checkpoint.after_sequence,
      reason: checkpoint.reason,
      created_by: checkpoint.created_by,
      active: checkpoint.active,
      created_at: checkpoint.inserted_at,
      deactivated_at: checkpoint.deactivated_at
    }
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
