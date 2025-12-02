defmodule MrMunchMeAccountingApp.Repo do
  use Ecto.Repo,
    otp_app: :mr_munch_me_accounting_app,
    adapter: Ecto.Adapters.Postgres
end
