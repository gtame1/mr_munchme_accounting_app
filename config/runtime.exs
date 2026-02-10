import Config

# Configure repo from DATABASE_URL if provided (for production/staging)
# For local development, use dev.exs configuration instead
if database_url = System.get_env("DATABASE_URL") do
  db_uri = URI.parse(database_url)

  config :ledgr, Ledgr.Repo,
    url: database_url,
    ssl: [
      verify: :verify_none,
      server_name_indication: to_charlist(db_uri.host || "")
    ],
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "2")
end

# Only configure server when running the app (not when building)
if System.get_env("PHX_SERVER") do
  config :ledgr, LedgrWeb.Endpoint, server: true
end

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "SECRET_KEY_BASE missing"

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :ledgr, LedgrWeb.Endpoint,
    url: [host: host, scheme: "https", port: 443],
    http: [ip: {0,0,0,0,0,0,0,0}, port: port],
    secret_key_base: secret_key_base
end
