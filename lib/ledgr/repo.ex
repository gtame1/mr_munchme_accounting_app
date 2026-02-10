defmodule Ledgr.Repo do
  use Ecto.Repo,
    otp_app: :ledgr,
    adapter: Ecto.Adapters.Postgres

  @impl true
  def init(_type, config) do
    require Logger
    {:ok, config}
  end
end
