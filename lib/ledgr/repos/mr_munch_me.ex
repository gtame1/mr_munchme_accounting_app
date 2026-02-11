defmodule Ledgr.Repos.MrMunchMe do
  use Ecto.Repo,
    otp_app: :ledgr,
    adapter: Ecto.Adapters.Postgres
end
