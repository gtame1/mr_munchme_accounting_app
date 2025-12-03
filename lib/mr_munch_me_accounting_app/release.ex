defmodule MrMunchMeAccountingApp.Release do
  @moduledoc """
  Release tasks for running migrations and seeds in production.
  These are meant to be invoked via:

      bin/mr_munch_me_accounting_app eval "MrMunchMeAccountingApp.Release.migrate"
      bin/mr_munch_me_accounting_app eval "MrMunchMeAccountingApp.Release.seed"
  """

  @app :mr_munch_me_accounting_app

  # This is what Render calls via `eval` before starting the app.
  def migrate do
    IO.puts("🚀 Starting application and running migrations + seeds...")

    # Start the app and all its deps (including Repo + Ecto registry)
    {:ok, _} = Application.ensure_all_started(@app)

    # 1) Run migrations for all repos
    for repo <- repos() do
      IO.puts("➡ Migrating #{inspect(repo)}...")
      Ecto.Migrator.run(repo, :up, all: true)
    end

    # 2) Run seeds once migrations are done
    run_seeds()

    IO.puts("✅ Migrations and seeds complete")
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp run_seeds do
    seed_path = Application.app_dir(@app, "priv/repo/seeds.exs")

    if File.exists?(seed_path) do
      IO.puts("🌱 Running seeds from #{seed_path}...")
      Code.eval_file(seed_path)
      IO.puts("🌱 Seeds finished successfully")
    else
      IO.puts("⚠️ No seeds.exs found, skipping")
    end
  end
end
