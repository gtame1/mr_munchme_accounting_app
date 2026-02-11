defmodule Ledgr.Release do
  @moduledoc """
  Release tasks for running migrations and seeds in production.
  These are meant to be invoked via:

      bin/ledgr eval "Ledgr.Release.migrate"
      bin/ledgr eval "Ledgr.Release.seed"
  """

  @app :ledgr

  @repo_seed_paths %{
    Ledgr.Repos.MrMunchMe => "priv/repos/mr_munch_me/seeds.exs",
    Ledgr.Repos.Viaxe => "priv/repos/viaxe/seeds.exs"
  }

  # This is what Render calls via `eval` before starting the app.
  def migrate do
    IO.puts("Starting application and running migrations + seeds...")

    # Start the app and all its deps (including Repos + Ecto registry)
    {:ok, _} = Application.ensure_all_started(@app)

    # 1) Run migrations for all repos
    for repo <- repos() do
      IO.puts("Migrating #{inspect(repo)}...")
      Ecto.Migrator.run(repo, :up, all: true)
    end

    # 2) Run seeds for each repo
    run_seeds()

    IO.puts("Migrations and seeds complete")
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp run_seeds do
    for {repo, seed_path} <- @repo_seed_paths do
      full_path = Application.app_dir(@app, seed_path)

      if File.exists?(full_path) do
        IO.puts("Running seeds for #{inspect(repo)} from #{full_path}...")
        Ledgr.Repo.put_active_repo(repo)
        Code.eval_file(full_path)
        IO.puts("Seeds finished for #{inspect(repo)}")
      else
        IO.puts("No seeds found for #{inspect(repo)}, skipping")
      end
    end
  end
end
