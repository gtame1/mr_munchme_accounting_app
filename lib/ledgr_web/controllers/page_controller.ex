defmodule LedgrWeb.PageController do
  use LedgrWeb, :controller

  def home(conn, _params) do
    case conn.assigns[:current_domain] do
      nil -> render(conn, :home)
      domain -> redirect(conn, to: "#{domain.path_prefix()}/login")
    end
  end

  def apps(conn, _params) do
    domains =
      Application.get_env(:ledgr, :domains, [])
      |> Enum.map(fn mod ->
        %{
          name: mod.name(),
          logo: mod.logo(),
          path: "#{mod.path_prefix()}/login",
          theme: mod.theme()
        }
      end)

    render(conn, :apps, domains: domains)
  end
end
