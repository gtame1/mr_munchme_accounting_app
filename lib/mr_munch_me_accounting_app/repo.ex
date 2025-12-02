defmodule MrMunchMeAccountingApp.Repo do
  use Ecto.Repo,
    otp_app: :mr_munch_me_accounting_app,
    adapter: Ecto.Adapters.Postgres

  @impl true
  def init(_type, config) do
    require Logger
    Logger.info("📦 Repo init config: #{inspect(config, pretty: true)}")
    {:ok, config}
  end
end
