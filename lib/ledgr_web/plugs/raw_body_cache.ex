defmodule LedgrWeb.Plugs.RawBodyCache do
  @moduledoc """
  Custom body reader for Plug.Parsers that caches the raw request body
  in conn.assigns.raw_body before it is parsed.

  Required for Stripe webhook signature verification, which needs the
  original raw body bytes (not the parsed params).

  Plugged in via the body_reader option in LedgrWeb.SafeParser.
  """

  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        conn = Plug.Conn.assign(conn, :raw_body, (conn.assigns[:raw_body] || "") <> body)
        {:ok, body, conn}

      {:more, body, conn} ->
        conn = Plug.Conn.assign(conn, :raw_body, (conn.assigns[:raw_body] || "") <> body)
        {:more, body, conn}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
