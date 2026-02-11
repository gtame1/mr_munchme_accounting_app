defmodule LedgrWeb.RegistrationController do
  use LedgrWeb, :controller

  alias Ledgr.Core.Accounts
  alias Ledgr.Core.Accounts.User

  def new(conn, _params) do
    changeset = Accounts.change_registration(%User{})

    conn
    |> assign(:hide_sidebar, true)
    |> render(:new, changeset: changeset)
  end

  def create(conn, %{"user" => user_params}) do
    case Accounts.create_user(user_params) do
      {:ok, user} ->
        domain = conn.assigns[:current_domain]
        session_key = "user_id:#{domain.slug()}"

        conn
        |> configure_session(renew: true)
        |> put_session(session_key, user.id)
        |> put_flash(:info, "Account created successfully!")
        |> redirect(to: domain.path_prefix())

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> assign(:hide_sidebar, true)
        |> render(:new, changeset: changeset)
    end
  end
end

defmodule LedgrWeb.RegistrationHTML do
  use LedgrWeb, :html

  embed_templates "registration_html/*"
end
