defmodule Mix.Tasks.ResetAndSeed do
  use Mix.Task

  @shortdoc "Clears ALL data and reruns priv/repo/seeds.exs"

  def run(_args) do
    Mix.Task.run("app.start")

    IO.puts("\n🚨 Running reset_all tables...\n")
    Mix.Task.run("reset_all_tables")

    IO.puts("\n🌱 Running priv/repo/seeds.exs...\n")
    Code.require_file("priv/repo/seeds.exs")

    IO.puts("\n✅ Reset + Seed completed\n")
  end
end
