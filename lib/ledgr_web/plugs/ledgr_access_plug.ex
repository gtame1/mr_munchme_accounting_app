defmodule LedgrWeb.Plugs.LedgrAccessPlug do
  @moduledoc """
  Gates the Ledgr landing page (/ and /apps) behind a simple site password.

  Only protects the two Ledgr-specific landing paths. All app routes (/app/*),
  storefronts (/<slug>/*), and custom domains bypass this entirely — they have
  their own per-app authentication.

  If LEDGR_PASSWORD is not set, the plug is a no-op (no protection).
  """

  import Plug.Conn
  import Phoenix.Controller

  @unlock_path "/unlock"

  # Only these paths require the ledgr site password.
  @protected_paths [[], ["apps"]]

  def init(opts), do: opts

  def call(conn, _opts) do
    password = System.get_env("LEDGR_PASSWORD")

    cond do
      # No password configured — skip protection
      is_nil(password) or password == "" ->
        conn

      # Only protect the landing page (/) and app picker (/apps)
      conn.path_info not in @protected_paths ->
        conn

      # Already authenticated
      get_session(conn, :ledgr_access) == true ->
        conn

      # Not authenticated — redirect to unlock
      true ->
        conn
        |> put_session(:ledgr_return_to, conn.request_path)
        |> redirect(to: @unlock_path)
        |> halt()
    end
  end

end
