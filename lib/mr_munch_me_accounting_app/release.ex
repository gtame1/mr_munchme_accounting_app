defmodule MrMunchMeAccountingApp.Release do
  @app :mr_munch_me_accounting_app

  def migrate do
    IO.puts("🚀 Running migrations...")

    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    IO.puts("✅ Migrations complete")
  end

  def seed do
    {:ok, _} = Application.ensure_all_started(@app)

    seed_path = Application.app_dir(@app, "priv/repo/seeds.exs")

    if File.exists?(seed_path) do
      IO.puts("🌱 Running seeds...")
      Code.eval_file(seed_path)
    else
      IO.puts("⚠️ No seeds.exs found")
    end
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  defp load_app, do: Application.load(@app)
end
