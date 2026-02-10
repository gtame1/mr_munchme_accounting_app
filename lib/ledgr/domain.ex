defmodule Ledgr.Domain do
  @moduledoc """
  Helper to access the currently configured domain module.

  The active domain is set via:

      config :ledgr, :domain, Ledgr.Domains.MrMunchMe

  The domain module must implement the behaviours defined in
  `Ledgr.Domain.DomainConfig`, `Ledgr.Domain.RevenueHandler`,
  and `Ledgr.Domain.DashboardProvider`.
  """

  @doc "Returns the currently configured domain module."
  def current do
    Application.get_env(:ledgr, :domain)
  end
end
