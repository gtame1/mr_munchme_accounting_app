defmodule Ledgr.Domain do
  @moduledoc """
  Helper to access the currently active domain module.

  The active domain can be set per-request via process dictionary
  (by DomainPlug), or falls back to the application config:

      config :ledgr, :domain, Ledgr.Domains.MrMunchMe

  The domain module must implement the behaviours defined in
  `Ledgr.Domain.DomainConfig`, `Ledgr.Domain.RevenueHandler`,
  and `Ledgr.Domain.DashboardProvider`.
  """

  @doc "Returns the currently active domain module."
  def current do
    Process.get(:ledgr_active_domain) ||
      Application.get_env(:ledgr, :domain) ||
      Application.get_env(:ledgr, :default_domain)
  end

  @doc "Sets the active domain for the current process."
  def put_current(domain_module) do
    Process.put(:ledgr_active_domain, domain_module)
  end
end
