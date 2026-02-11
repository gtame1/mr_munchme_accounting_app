defmodule LedgrWeb.PageController do
  use LedgrWeb, :controller

  def home(conn, _params) do
    domains =
      Application.get_env(:ledgr, :domains, [])
      |> Enum.map(fn domain_module ->
        %{
          name: domain_module.name(),
          slug: domain_module.slug(),
          path: domain_module.path_prefix(),
          logo: domain_module.logo(),
          theme: domain_module.theme()
        }
      end)

    render(conn, :home, domains: domains)
  end
end
