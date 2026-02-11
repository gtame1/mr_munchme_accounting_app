# Set the active repo for Viaxe
Ledgr.Repo.put_active_repo(Ledgr.Repos.Viaxe)

# Load core seeds (shared across all domains)
Code.eval_file("priv/repos/mr_munch_me/seeds/core_seeds.exs")

# Load Viaxe domain seeds
seed_file = "priv/repos/viaxe/seeds/viaxe_seeds.exs"

if File.exists?(seed_file) do
  IO.puts("Loading Viaxe domain seeds: #{seed_file}")
  Code.eval_file(seed_file)
end
