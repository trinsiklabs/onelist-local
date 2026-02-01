defmodule OnelistWeb.PrivacyController do
  use OnelistWeb, :controller
  
  alias Onelist.Accounts
  alias Onelist.Privacy
  
  @doc """
  Download user data in machine-readable format (GDPR right to data portability)
  """
  def export_data(conn, _params) do
    user = conn.assigns.current_user
    
    if user do
      # Collect user data
      user_data = %{
        email: user.email,
        account_created: user.inserted_at,
        sessions: Onelist.Sessions.list_active_sessions(user)
                  |> Enum.map(&Privacy.anonymize_session_data/1)
      }
      
      # Log data export
      Privacy.log_privacy_action(:data_exported, %{user_id: user.id})
      
      # Return as JSON file
      conn
      |> put_resp_content_type("application/json")
      |> put_resp_header("content-disposition", "attachment; filename=user_data.json")
      |> send_resp(200, Jason.encode!(user_data))
    else
      conn
      |> put_flash(:error, "You must be logged in to export your data.")
      |> redirect(to: ~p"/login")
    end
  end
  
  @doc """
  Delete user account and all associated data
  """
  def delete_account(conn, %{"confirmation" => confirmation}) do
    user = conn.assigns.current_user
    
    if user && confirmation == "DELETE" do
      # Log deletion request
      Privacy.log_privacy_action(:account_deleted, %{user_id: user.id})
      
      # Clean up user data
      Privacy.cleanup_user_data(user.id)
      
      # Delete the user account
      Accounts.delete_user(user)
      
      # Clear session and redirect
      conn
      |> clear_session()
      |> put_flash(:info, "Your account has been deleted along with all associated data.")
      |> redirect(to: ~p"/")
    else
      conn
      |> put_flash(:error, "Account deletion requires confirmation.")
      |> redirect(to: ~p"/account/settings")
    end
  end
end 