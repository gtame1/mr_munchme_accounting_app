defmodule MrMunchMeAccountingAppWeb.ReportController do
  use MrMunchMeAccountingAppWeb, :controller

  alias MrMunchMeAccountingApp.Accounting
  alias MrMunchMeAccountingApp.Reporting
  alias MrMunchMeAccountingApp.Orders
  alias MrMunchMeAccountingApp.Inventory
  alias MrMunchMeAccountingApp.Inventory.Verification

  def dashboard(conn, params) do
    {start_date, end_date} = resolve_period(params)
    {earliest_date, latest_date} = Inventory.movement_date_range()

    metrics = Reporting.dashboard_metrics(start_date, end_date)

    render(conn, :dashboard,
      metrics: metrics,
      start_date: start_date,
      end_date: end_date,
      earliest_date: earliest_date,
      latest_date: latest_date
    )
  end

  # P&L for a period (default: current month)
  def pnl(conn, params) do
    {start_date, end_date} = resolve_period(params)
    {earliest_date, latest_date} = Inventory.movement_date_range()

    summary  = Accounting.profit_and_loss(start_date, end_date)
    monthly  = Accounting.profit_and_loss_monthly(5)  # last 6 months including current

    render(conn, :pnl,
      summary: summary,
      monthly: monthly,
      start_date: start_date,
      end_date: end_date,
      earliest_date: earliest_date,
      latest_date: latest_date
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

    {earliest_date, latest_date} = Inventory.movement_date_range()

    render(conn, :unit_economics,
      unit_economics: unit_economics_data,
      product_options: product_options,
      selected_product_id: product_id,
      start_date: start_date,
      end_date: end_date,
      earliest_date: earliest_date,
      latest_date: latest_date
    )
  end

  def cash_flow(conn, params) do
    {start_date, end_date} = resolve_period(params)
    {earliest_date, latest_date} = Inventory.movement_date_range()

    cash_flow_data = Reporting.cash_flow(start_date, end_date)

    render(conn, :cash_flow,
      cash_flow: cash_flow_data,
      start_date: start_date,
      end_date: end_date,
      earliest_date: earliest_date,
      latest_date: latest_date
    )
  end

  def unit_economics_list(conn, params) do
    {start_date, end_date} = resolve_period(params)
    {earliest_date, latest_date} = Inventory.movement_date_range()

    all_unit_economics = Reporting.all_unit_economics(start_date, end_date)

    # Calculate totals across all products
    totals = calculate_totals(all_unit_economics)

    render(conn, :unit_economics_list,
      all_unit_economics: all_unit_economics,
      totals: totals,
      start_date: start_date,
      end_date: end_date,
      earliest_date: earliest_date,
      latest_date: latest_date
    )
  end

  defp calculate_totals(all_unit_economics) do
    Enum.reduce(all_unit_economics, %{
      units_sold: 0,
      revenue_cents: 0,
      cogs_cents: 0,
      gross_margin_cents: 0,
      net_profit_cents: 0
    }, fn ue, acc ->
      %{
        units_sold: acc.units_sold + ue.units_sold,
        revenue_cents: acc.revenue_cents + ue.revenue_cents,
        cogs_cents: acc.cogs_cents + ue.cogs_cents,
        gross_margin_cents: acc.gross_margin_cents + ue.gross_margin_cents,
        net_profit_cents: acc.net_profit_cents + ue.net_profit_cents
      }
    end)
    |> then(fn totals ->
      gross_margin_percent =
        if totals.revenue_cents > 0 do
          Float.round(totals.gross_margin_cents / totals.revenue_cents * 100, 2)
        else
          0.0
        end

      net_margin_percent =
        if totals.revenue_cents > 0 do
          Float.round(totals.net_profit_cents / totals.revenue_cents * 100, 2)
        else
          0.0
        end

      # Calculate per-unit averages
      revenue_per_unit_cents = if totals.units_sold > 0, do: div(totals.revenue_cents, totals.units_sold), else: 0
      cogs_per_unit_cents = if totals.units_sold > 0, do: div(totals.cogs_cents, totals.units_sold), else: 0
      gross_margin_per_unit_cents = if totals.units_sold > 0, do: div(totals.gross_margin_cents, totals.units_sold), else: 0

      totals
      |> Map.put(:gross_margin_percent, gross_margin_percent)
      |> Map.put(:net_margin_percent, net_margin_percent)
      |> Map.put(:revenue_per_unit_cents, revenue_per_unit_cents)
      |> Map.put(:cogs_per_unit_cents, cogs_per_unit_cents)
      |> Map.put(:gross_margin_per_unit_cents, gross_margin_per_unit_cents)
    end)
  end

  def inventory_verification(conn, _params) do
    results = Verification.run_all_checks()

    # Handle repair action (POST request)
    if conn.method == "POST" do
      case Verification.repair_inventory_quantities() do
        {:ok, repairs_list} when repairs_list != [] ->
          # Store repairs in session and redirect
          conn
          |> put_session(:repair_results, repairs_list)
          |> redirect(to: ~p"/reports/inventory_verification#repair-results")
        {:ok, []} ->
          # No repairs needed
          render(conn, :inventory_verification,
            results: results,
            repairs: []
          )
        {:error, _reason} ->
          render(conn, :inventory_verification,
            results: results,
            repairs: []
          )
      end
    else
      # GET request - retrieve repairs from session
      repairs = get_session(conn, :repair_results) || []

      # Clear repair results from session after reading
      conn = delete_session(conn, :repair_results)

      render(conn, :inventory_verification,
        results: results,
        repairs: repairs
      )
    end
  end

  # Helpers

  defp resolve_period(%{"period" => "last_7_days"}) do
    today = Date.utc_today()
    {Date.add(today, -6), today}
  end

  defp resolve_period(%{"period" => "this_month"}) do
    today = Date.utc_today()
    start_of_month = %Date{today | day: 1}
    {start_of_month, today}
  end

  defp resolve_period(%{"period" => "last_90_days"}) do
    today = Date.utc_today()
    {Date.add(today, -89), today}
  end

  defp resolve_period(%{"all_dates" => "true"}) do
    {earliest_date, latest_date} = Inventory.movement_date_range()

    case {earliest_date, latest_date} do
      {nil, nil} ->
        # No movements exist, default to current month
        today = Date.utc_today()
        start_of_month = %Date{today | day: 1}
        {start_of_month, today}
      {earliest, latest} ->
        {earliest, latest}
    end
  end

  # Alias for "all_time" period
  defp resolve_period(%{"period" => "all_time"}), do: resolve_period(%{"all_dates" => "true"})

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

  defp format_check_name(name) do
    name
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp get_check_explanation(:inventory_quantities) do
    "Verifies that stored inventory quantities match the sum of all movements (purchases, usages, transfers). " <>
    "If mismatched, use the 'Repair Quantities' button to recalculate from movements, or use Inventory Reconciliation to record physical counts."
  end

  defp get_check_explanation(:wip_balance) do
    "Verifies that the Work-In-Progress (WIP) account balance matches the net WIP from journal entries " <>
    "(debits from orders in prep minus credits from orders delivered). If mismatched, review order status changes and journal entries."
  end

  defp get_check_explanation(:inventory_cost_accounting) do
    "Verifies that the total value of inventory items (quantity × average cost) matches the Ingredients Inventory account balance. " <>
    "If mismatched, review inventory purchases, cost updates, and journal entries affecting the inventory account."
  end

  defp get_check_explanation(:order_wip_consistency) do
    "Verifies that orders moved to 'in prep' have corresponding 'delivered' entries, and that WIP debits equal credits for delivered orders. " <>
    "If inconsistent, ensure all orders follow the complete workflow: in_prep → delivered, and review order status changes."
  end

  defp get_check_explanation(:journal_entries_balanced) do
    "Verifies that all journal entries have balanced debits and credits (total debits = total credits). " <>
    "This is a fundamental accounting rule. If unbalanced, review the journal entry creation logic and manually correct entries."
  end

  defp get_check_explanation(_) do
    "Verification check"
  end

  defp format_key(key) do
    key
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp format_value(key, value) when is_integer(value) do
    # Check if this key represents a count, not a currency
    count_keys = [:checked_entries, :unbalanced, :checked_items, :checked_orders, :issues]

    if key in count_keys do
      # Format as plain number
      Integer.to_string(value)
    else
      # Format cents as currency (handle negative numbers correctly)
      abs_value = abs(value)
      pesos = div(abs_value, 100)
      cents_remainder = rem(abs_value, 100)
      sign = if value < 0, do: "-", else: ""
      "#{sign}#{pesos}.#{String.pad_leading(Integer.to_string(cents_remainder), 2, "0")} MXN"
    end
  end

  defp format_value(_key, value) when is_list(value) do
    "#{length(value)} items"
  end

  defp format_value(_key, value) do
    inspect(value)
  end
end
