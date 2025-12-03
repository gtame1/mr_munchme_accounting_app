defmodule MrMunchMeAccountingApp.Release do
  @moduledoc """
  Release tasks for running migrations and seeds in production.
  These are meant to be invoked via:

      bin/mr_munch_me_accounting_app eval "MrMunchMeAccountingApp.Release.migrate"
      bin/mr_munch_me_accounting_app eval "MrMunchMeAccountingApp.Release.seed"
  """

  @app :mr_munch_me_accounting_app

  # Run all pending migrations for all repos
  def migrate do
    IO.puts("🚀 Running migrations (and seeds)...")

    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          # 1) Run all migrations
          Ecto.Migrator.run(repo, :up, all: true)

          # 2) Run seeds WHILE this repo is started
          run_seeds_for_repo(repo)
        end)
    end

    IO.puts("✅ Migrations and seeds complete")
  end

  defp run_seeds_for_repo(repo) do
    seed_path = Application.app_dir(@app, "priv/repo/seeds.exs")

    if File.exists?(seed_path) do
      IO.puts("🌱 Running seeds for #{inspect(repo)} from #{seed_path}...")
      Code.eval_file(seed_path)
      IO.puts("✅ Seeds done for #{inspect(repo)}")
    else
      IO.puts("⚠️ No seeds.exs found, skipping")
    end
  end

  # --- Helpers ---

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Make sure the application and its config are loaded
    case Application.load(@app) do
      :ok -> :ok
      {:error, {:already_loaded, _}} -> :ok
      error -> raise "Failed to load application: #{inspect(error)}"
    end
  end
end
