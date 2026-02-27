defmodule Ledgr.Release do
  @moduledoc """
  Release tasks for running migrations and seeds in production.

  ## Usage

      # Run on every deploy (via Render preDeployCommand):
      bin/ledgr eval "Ledgr.Release.migrate()"

      # Run once after first deploy to seed required business data:
      bin/ledgr eval "Ledgr.Release.seed()"

      # Or via the named release commands (defined in mix.exs):
      bin/ledgr migrate
      bin/ledgr seed
  """

  @app :ledgr

  # Production seed files — real business data only, no dummy/sample records.
  @prod_seed_paths %{
    Ledgr.Repos.MrMunchMe => "priv/repos/mr_munch_me/seeds_prod.exs",
    Ledgr.Repos.Viaxe     => "priv/repos/viaxe/seeds_prod.exs"
  }

  @doc """
  Runs all pending Ecto migrations for every configured repo.

  Called on every deploy via Render's preDeployCommand. Safe to run
  repeatedly — Ecto skips already-applied migrations.
  """
  def migrate do
    IO.puts("==> Running migrations...")
    {:ok, _} = Application.ensure_all_started(@app)

    for repo <- repos() do
      IO.puts("    Migrating #{inspect(repo)}...")
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    IO.puts("==> Migrations complete.")
  end

  @doc """
  Seeds required production data for all repos (chart of accounts, products,
  ingredients, recipes, suppliers, services, admin user).

  Run ONCE after the first deploy — or after a database reset.
  Safe to run again (all seeds are idempotent).
  """
  def seed do
    IO.puts("==> Running production seeds...")
    {:ok, _} = Application.ensure_all_started(@app)

    for {repo, seed_path} <- @prod_seed_paths do
      full_path = Application.app_dir(@app, seed_path)

      if File.exists?(full_path) do
        IO.puts("    Seeding #{inspect(repo)} from #{seed_path}...")
        Ledgr.Repo.put_active_repo(repo)
        Code.eval_file(full_path)
        IO.puts("    Done seeding #{inspect(repo)}.")
      else
        IO.puts("    WARNING: seed file not found for #{inspect(repo)}: #{full_path}")
      end
    end

    IO.puts("==> Seeds complete.")
  end

  # ── Private ──────────────────────────────────────────────

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end
end
