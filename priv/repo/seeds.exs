# Load core seeds (shared across all domains)
Code.eval_file("priv/repo/seeds/core_seeds.exs")

# Load domain-specific seeds
domain = Application.get_env(:ledgr, :domain)

if domain && Code.ensure_loaded?(domain) && function_exported?(domain, :seed_file, 0) do
  seed_file = domain.seed_file()

  if seed_file && File.exists?(seed_file) do
    IO.puts("Loading domain seeds: #{seed_file}")
    Code.eval_file(seed_file)
  end
end
