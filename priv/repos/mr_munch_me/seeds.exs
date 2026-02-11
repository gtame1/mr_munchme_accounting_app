# Set the active repo for MrMunchMe
Ledgr.Repo.put_active_repo(Ledgr.Repos.MrMunchMe)

# Load core seeds (shared across all domains)
Code.eval_file("priv/repos/mr_munch_me/seeds/core_seeds.exs")

# Load MrMunchMe domain seeds
seed_file = "priv/repos/mr_munch_me/seeds/mr_munch_me_seeds.exs"

if File.exists?(seed_file) do
  IO.puts("Loading MrMunchMe domain seeds: #{seed_file}")
  Code.eval_file(seed_file)
end
