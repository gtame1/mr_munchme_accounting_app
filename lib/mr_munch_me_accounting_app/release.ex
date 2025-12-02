defmodule MrMunchMeAccountingApp.Release do
  @moduledoc """
  Helpers for running tasks in the release (like migrations).
  """

  @app :mr_munch_me_accounting_app

  def migrate do
    IO.puts("🧱 Running database migrations...")

    load_app()

    for repo <- repos() do
      IO.puts("➡ Migrating #{inspect(repo)}")
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    IO.puts("✅ Migrations finished.")
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
