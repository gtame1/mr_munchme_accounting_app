defmodule LedgrWeb.UnlockController do
  use LedgrWeb, :controller

  def new(conn, _params) do
    render(conn, :new, error: nil)
  end

  def create(conn, %{"password" => password}) do
    expected = System.get_env("LEDGR_PASSWORD", "")

    if expected != "" and password == expected do
      return_to = get_session(conn, :ledgr_return_to) || "/apps"

      conn
      |> put_session(:ledgr_access, true)
      |> delete_session(:ledgr_return_to)
      |> redirect(to: return_to)
    else
      render(conn, :new, error: "Incorrect password.")
    end
  end
end
