defmodule Mix.Tasks.SeedNewTables do
  use Mix.Task

  @shortdoc "Runs priv/repo/seeds.exs"

  def run(_args) do
    Mix.Task.run("app.start")

    IO.puts("\n🌱 Running priv/repo/seeds.exs...\n")
    Code.require_file("priv/repo/seeds.exs")

    IO.puts("\n✅ Seed completed\n")
  end
end
