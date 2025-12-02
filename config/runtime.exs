import Config

if System.get_env("PHX_SERVER") do
  config :mr_munch_me_accounting_app, MrMunchMeAccountingAppWeb.Endpoint, server: true
end

if config_env() == :prod do
  # ---------- Repo (database) ----------

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  db_uri = URI.parse(database_url)

  maybe_ipv6 =
    if System.get_env("ECTO_IPV6") in ~w(true 1),
      do: [:inet6],
      else: []

  config :mr_munch_me_accounting_app, MrMunchMeAccountingApp.Repo,
    url: database_url,
    ssl: true,
    ssl_opts: [
      verify: :verify_none,
      server_name_indication: to_charlist(db_uri.host || "")
    ],
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  # ---------- Endpoint ----------

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :mr_munch_me_accounting_app, MrMunchMeAccountingAppWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # ---------- Misc ----------

  config :mr_munch_me_accounting_app, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :swoosh, api_client: Swoosh.ApiClient.Req
  config :swoosh, local: false
  config :logger, level: :info
end
