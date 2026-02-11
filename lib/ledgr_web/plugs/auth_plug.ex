defmodule LedgrWeb.Plugs.AuthPlug do
  @moduledoc """
  Plug that checks for an authenticated user in the session.

  Must run AFTER DomainPlug since it needs the domain context
  to determine which session key to check.

  Session keys are domain-scoped: "user_id:mr-munch-me", "user_id:viaxe"
  to prevent cross-domain session bleed.
  """

  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    domain = conn.assigns[:current_domain]

    if domain do
      session_key = "user_id:#{domain.slug()}"
      user_id = get_session(conn, session_key)

      if user_id do
        user = Ledgr.Repo.get(Ledgr.Core.Accounts.User, user_id)

        if user do
          assign(conn, :current_user, user)
        else
          # Stale session — user was deleted
          conn
          |> clear_session()
          |> redirect(to: "#{domain.path_prefix()}/login")
          |> halt()
        end
      else
        conn
        |> redirect(to: "#{domain.path_prefix()}/login")
        |> halt()
      end
    else
      # No domain context (landing page) — skip auth
      conn
    end
  end
end
