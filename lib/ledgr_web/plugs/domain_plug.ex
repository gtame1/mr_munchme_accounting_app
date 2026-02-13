defmodule LedgrWeb.Plugs.DomainPlug do
  @moduledoc """
  Plug that sets the active domain and repo based on the URL path prefix.

  Reads the domain slug from the URL (e.g., `/app/mr-munch-me/...`) and sets:
  - `Process.put(:ledgr_active_domain, domain_module)` for `Ledgr.Domain.current()`
  - `Process.put(:ledgr_repo, repo_module)` for `Ledgr.Repo` delegation
  - `conn.assigns[:current_domain]` for use in templates
  - `conn.assigns[:domain_path_prefix]` for building domain-scoped paths
  """

  import Plug.Conn

  @domain_slugs %{
    "mr-munch-me" => Ledgr.Domains.MrMunchMe,
    "viaxe" => Ledgr.Domains.Viaxe
  }

  def init(opts), do: opts

  def call(conn, _opts) do
    case conn.path_info do
      ["app", slug | _rest] ->
        set_domain_context(conn, slug)

      # Public storefront routes: /<domain-slug>/menu/...
      [slug | _rest] ->
        case Map.get(@domain_slugs, slug) do
          nil -> conn
          _domain_module -> set_domain_context(conn, slug)
        end

      _ ->
        conn
    end
  end

  defp set_domain_context(conn, slug) do
    case Map.get(@domain_slugs, slug) do
      nil ->
        conn

      domain_module ->
        repo = Ledgr.Repo.repo_for_domain(domain_module)

        # Set process dictionary for dynamic dispatch
        Ledgr.Domain.put_current(domain_module)
        Ledgr.Repo.put_active_repo(repo)

        # Set conn assigns for templates
        conn
        |> assign(:current_domain, domain_module)
        |> assign(:domain_path_prefix, domain_module.path_prefix())
    end
  end
end
