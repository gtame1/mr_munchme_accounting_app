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
    IO.puts("🚀 Running migrations...")

    load_app()

    for repo <- repos() do
      IO.puts("➡ Migrating #{inspect(repo)}")

      {:ok, _pid, _apps} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          Ecto.Migrator.run(repo, :up, all: true)
        end)
    end

    IO.puts("✅ Migrations complete")

    run_seeds()
  end

  # Run priv/repo/seeds.exs (if present)
  defp run_seeds() do
    IO.puts("🌱 Running seeds...")

    load_app()

    seed_path = Application.app_dir(@app, "priv/repo/seeds.exs")

    if File.exists?(seed_path) do
      IO.puts("➡ Executing #{seed_path}")
      Code.eval_file(seed_path)
      IO.puts("✅ Seeds complete")
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
