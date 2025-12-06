defmodule MrMunchMeAccountingAppWeb.ReportController do
  use MrMunchMeAccountingAppWeb, :controller

  alias MrMunchMeAccountingApp.Accounting
  alias MrMunchMeAccountingApp.Reporting
  alias MrMunchMeAccountingApp.Orders

  def dashboard(conn, params) do
    {start_date, end_date} = resolve_period(params)

    metrics = Reporting.dashboard_metrics(start_date, end_date)

    render(conn, :dashboard,
      metrics: metrics,
      start_date: start_date,
      end_date: end_date
    )
  end

  # P&L for a period (default: current month)
  def pnl(conn, params) do
    {start_date, end_date} = resolve_period(params)

    summary  = Accounting.profit_and_loss(start_date, end_date)
    monthly  = Accounting.profit_and_loss_monthly(5)  # last 6 months including current

    render(conn, :pnl,
      summary: summary,
      monthly: monthly,
      start_date: start_date,
      end_date: end_date
    )
  end

  # Balance sheet as of a given date (default: today)
  def balance_sheet(conn, params) do
    as_of =
      case Map.get(params, "as_of") do
        nil -> Date.utc_today()
        "" -> Date.utc_today()
        date_str -> Date.from_iso8601!(date_str)
      end

    bs = Accounting.balance_sheet(as_of)

    render(conn, :balance_sheet,
      balance_sheet: bs,
      as_of: as_of
    )
  end

  def unit_economics(conn, params) do
    {start_date, end_date} = resolve_period(params)

    # Get product_id from params, default to first product if not provided
    product_options = Orders.product_select_options()

    product_id =
      case Map.get(params, "product_id") do
        nil ->
          # Get first active product
          case product_options do
            [{_label, id} | _] -> id
            [] -> nil
          end
        "" -> nil
        id_str when is_binary(id_str) ->
          case Integer.parse(id_str) do
            {id, _} -> id
            :error -> nil
          end
        id when is_integer(id) ->
          id
        _ ->
          nil
      end

    unit_economics_data =
      if product_id do
        try do
          Reporting.unit_economics(product_id, start_date, end_date)
        rescue
          Ecto.NoResultsError ->
            # Product doesn't exist - return nil
            nil
        end
      else
        nil
      end

    render(conn, :unit_economics,
      unit_economics: unit_economics_data,
      product_options: product_options,
      selected_product_id: product_id,
      start_date: start_date,
      end_date: end_date
    )
  end

  def cash_flow(conn, params) do
    {start_date, end_date} = resolve_period(params)

    cash_flow_data = Reporting.cash_flow(start_date, end_date)

    render(conn, :cash_flow,
      cash_flow: cash_flow_data,
      start_date: start_date,
      end_date: end_date
    )
  end

  # Helpers

  defp resolve_period(%{"start_date" => s, "end_date" => e}) when s != "" and e != "" do
    {:ok, start_date} = Date.from_iso8601(s)
    {:ok, end_date} = Date.from_iso8601(e)
    {start_date, end_date}
  end

  defp resolve_period(_params) do
    today = Date.utc_today()
    start_of_month = %Date{today | day: 1}
    {start_of_month, today}
  end
end


defmodule MrMunchMeAccountingAppWeb.ReportHTML do
  use MrMunchMeAccountingAppWeb, :html

  import MrMunchMeAccountingAppWeb.CoreComponents

  embed_templates "report_html/*"
end
