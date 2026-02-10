defmodule Ledgr.Domain.DashboardProvider do
  @moduledoc """
  Behaviour for domain-specific dashboard metrics.

  Each business type implements this to provide its own KPIs and
  operational metrics for the dashboard view.
  """

  @doc "Returns domain-specific metrics for the dashboard within a date range."
  @callback dashboard_metrics(Date.t(), Date.t()) :: map()
end
