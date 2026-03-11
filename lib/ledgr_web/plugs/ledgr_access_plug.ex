defmodule LedgrWeb.Plugs.LedgrAccessPlug do
  @moduledoc """
  Gates access to ledgr.mx behind a simple site password.

  Requests coming from a known custom domain (e.g. mrmunchme.com, set via
  DOMAIN_HOSTS) bypass this check entirely — those domains have their own
  per-app authentication.

  If LEDGR_PASSWORD is not set, the plug is a no-op (no protection).
  """

  import Plug.Conn
  import Phoenix.Controller

  @unlock_path "/unlock"

  def init(opts), do: opts

  def call(conn, _opts) do
    password = System.get_env("LEDGR_PASSWORD")

    cond do
      # No password configured — skip protection
      is_nil(password) or password == "" ->
        conn

      # Custom domain (e.g. mrmunchme.com) — skip, handled by per-app auth
      custom_domain?(conn) ->
        conn

      # The unlock page itself — always allow through
      conn.path_info == ["unlock"] ->
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

  defp custom_domain?(conn) do
    hosts = Application.get_env(:ledgr, :domain_hosts, %{})
    Map.has_key?(hosts, String.downcase(conn.host))
  end
end
