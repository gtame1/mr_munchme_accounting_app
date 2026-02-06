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

    # Check for flash message from year_end_close action
    render(conn, :balance_sheet,
      balance_sheet: bs,
      as_of: as_of
    )
  end

  # Year-end close action
  def year_end_close(conn, params) do
    close_date =
      case Map.get(params, "close_date") do
        nil -> Date.new!(Date.utc_today().year - 1, 12, 31)
        "" -> Date.new!(Date.utc_today().year - 1, 12, 31)
        date_str -> Date.from_iso8601!(date_str)
      end

    case Accounting.close_year_end(close_date) do
      {:ok, :nothing_to_close} ->
        conn
        |> put_flash(:info, "No income or drawings to close for #{close_date}.")
        |> redirect(to: ~p"/reports/balance_sheet")

      {:ok, _entry} ->
        conn
        |> put_flash(:info, "Year-end close completed successfully for #{close_date}.")
        |> redirect(to: ~p"/reports/balance_sheet")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Year-end close failed: #{reason}")
        |> redirect(to: ~p"/reports/balance_sheet")
    end
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

  def diagnostics(conn, params) do
    results = Verification.run_all_checks()

    # Handle repair action (POST request)
    if conn.method == "POST" do
      repair_type = Map.get(params, "repair_type", "inventory_quantities")

      case Verification.run_repair(repair_type) do
        {:ok, repairs_list} when is_list(repairs_list) ->
          conn
          |> put_session(:repair_results, %{type: repair_type, results: repairs_list})
          |> redirect(to: ~p"/reports/diagnostics#repair-results")

        {:error, reason} ->
          conn
          |> put_session(:repair_results, %{type: repair_type, error: inspect(reason)})
          |> redirect(to: ~p"/reports/diagnostics#repair-results")
      end
    else
      # GET request - retrieve repair results from session
      repair_results = get_session(conn, :repair_results)
      conn = delete_session(conn, :repair_results)

      render(conn, :diagnostics,
        results: results,
        repair_results: repair_results
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
        {earliest, Enum.max([latest, Date.utc_today()], Date)}
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
    "Repair adjusts via Inventory Waste & Shrinkage (6060) to avoid affecting COGS."
  end

  defp get_check_explanation(:order_wip_consistency) do
    "Verifies that orders moved to 'in prep' have corresponding 'delivered' entries, and that WIP debits equal credits for delivered orders. " <>
    "If inconsistent, ensure all orders follow the complete workflow: in_prep → delivered, and review order status changes."
  end

  defp get_check_explanation(:journal_entries_balanced) do
    "Verifies that all journal entries have balanced debits and credits (total debits = total credits). " <>
    "This is a fundamental accounting rule. If unbalanced, review the journal entry creation logic and manually correct entries."
  end

  defp get_check_explanation(:withdrawal_accounts) do
    "Verifies that withdrawal entries debit Owner's Drawings (3100) instead of Owner's Equity (3000). " <>
    "Historical entries may have used the wrong account."
  end

  defp get_check_explanation(:duplicate_cogs_entries) do
    "Checks for duplicate journal entries for the same order (same reference, multiple entries). " <>
    "Duplicates inflate COGS and WIP values."
  end

  defp get_check_explanation(:gift_order_accounting) do
    "Verifies that delivered orders marked as gifts have proper gift accounting " <>
    "(Dr Samples & Gifts 6070, Cr WIP 1220) instead of sale-style entries."
  end

  defp get_check_explanation(:movement_costs) do
    "Checks for inventory movements (usage/write-off) with $0 cost. " <>
    "These may have been recorded before purchases were added and need cost backfilling."
  end

  defp get_check_explanation(:duplicate_movements) do
    "Checks for duplicate inventory movements (same ingredient, location, type, quantity, date, and source). " <>
    "Duplicates inflate inventory counts and costs. Repair deletes duplicates and recalculates quantities."
  end

  defp get_check_explanation(:ar_balance) do
    "Verifies that Accounts Receivable (1100) per order matches the expected outstanding amount " <>
    "(order total minus payments received). Repair creates adjustment entries to correct AR mismatches."
  end

  defp get_check_explanation(:customer_deposits) do
    "Verifies that Customer Deposits (2200) are properly transferred to AR when orders are delivered. " <>
    "Stale deposits on delivered orders indicate the deposit-to-AR transfer was missed. " <>
    "Repair creates the missing Dr 2200 / Cr 1100 transfer entries."
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
    count_keys = [:checked_entries, :unbalanced, :checked_items, :checked_orders, :issues, :duplicate_groups, :zero_cost, :orders_in_prep, :checked]

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

  defp format_value(_key, value) when is_binary(value) do
    value
  end

  defp format_value(_key, value) do
    inspect(value)
  end
end
