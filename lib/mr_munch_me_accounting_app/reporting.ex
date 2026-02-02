defmodule MrMunchMeAccountingApp.Reporting do
  @moduledoc """
  High-level reporting queries for dashboards (combining Orders + Accounting).
  """

  import Ecto.Query, warn: false
  alias MrMunchMeAccountingApp.Repo

  alias MrMunchMeAccountingApp.Orders.{Order, Product}
  alias MrMunchMeAccountingApp.Accounting
  alias MrMunchMeAccountingApp.Accounting.JournalEntry
  alias MrMunchMeAccountingApp.Inventory

  @doc """
  Returns metrics for the dashboard for a date range.

  * Uses order *delivery_date* for operational stats
  * Uses Accounting.profit_and_loss/2 for financial stats
  """
  def dashboard_metrics(start_date, end_date) do
    # --- Operational: orders + revenue (from orders/products) ---
    order_rev_stats =
      from(o in Order,
        where:
          o.delivery_date >= ^start_date and
            o.delivery_date <= ^end_date and
            o.status != "canceled",
        select: %{
          order_count: count(o.id)
        }
      )
      |> Repo.one()

    # Revenue from orders – if you want to include shipping product, you can adjust later
    revenue_stats =
      from(o in Order,
        join: p in assoc(o, :product),
        where:
          o.delivery_date >= ^start_date and
            o.delivery_date <= ^end_date and
            o.status != "canceled",
        select: %{
          revenue_cents: coalesce(sum(p.price_cents), 0)
        }
      )
      |> Repo.one()

    orders_by_status =
      from(o in Order,
        where: o.delivery_date >= ^start_date and o.delivery_date <= ^end_date,
        group_by: o.status,
        select: {o.status, count(o.id)}
      )
      |> Repo.all()
      |> Enum.into(%{})

    total_orders = order_rev_stats.order_count || 0
    revenue_cents = revenue_stats.revenue_cents || 0

    avg_order_value_cents =
      if total_orders > 0 do
        div(revenue_cents, total_orders)
      else
        0
      end

    delivered_orders = Map.get(orders_by_status, "delivered", 0)

    # --- Orders per product with revenue and COGS ---
    shipping_fee = Accounting.shipping_fee_cents()

    orders_by_product_base =
      from(o in Order,
        join: p in assoc(o, :product),
        where:
          o.delivery_date >= ^start_date and
            o.delivery_date <= ^end_date and
            o.status != "canceled",
        group_by: [p.id, p.name, p.sku],
        select: %{
          product_id: p.id,
          product_name: p.name,
          product_sku: p.sku,
          order_count: count(o.id),
          revenue_cents: fragment("SUM(?) + SUM(CASE WHEN ? THEN ? ELSE 0 END)", p.price_cents, o.customer_paid_shipping, ^shipping_fee)
        },
        order_by: [desc: count(o.id)]
      )
      |> Repo.all()

    # Get order IDs for each product to calculate COGS
    product_order_ids =
      orders_by_product_base
      |> Enum.map(fn product -> product.product_id end)
      |> Enum.uniq()

    # Get all orders for these products in the period
    all_orders =
      if Enum.empty?(product_order_ids) do
        []
      else
        from(o in Order,
          where:
            o.delivery_date >= ^start_date and
              o.delivery_date <= ^end_date and
              o.status != "canceled" and
              o.product_id in ^product_order_ids,
          select: o.id
        )
        |> Repo.all()
      end

    # Get COGS by order from journal entries
    cogs_by_order =
      if Enum.empty?(all_orders) do
        %{}
      else
        reference_patterns = Enum.map(all_orders, fn id -> "Order ##{id}" end)

        base_query =
          from(je in JournalEntry,
            join: jl in assoc(je, :journal_lines),
            join: acc in assoc(jl, :account),
            where:
              je.entry_type == "order_delivered" and
                acc.code == "5000" and
                je.date >= ^start_date and
                je.date <= ^end_date
          )

        # Use exact matching with IN clause instead of ilike patterns
        # ilike("Order #1") would wrongly match "Order #10", "Order #11", etc.
        query =
          case reference_patterns do
            [] ->
              base_query
            patterns ->
              base_query
              |> where([je], je.reference in ^patterns)
          end

        from([je, jl, acc] in query,
          group_by: je.reference,
          select: {je.reference, sum(jl.debit_cents)}
        )
        |> Repo.all()
        |> Enum.into(%{}, fn {ref, cogs} ->
          order_id =
            case Regex.run(~r/#(\d+)/, ref) do
              [_, id_str] -> String.to_integer(id_str)
              _ -> nil
            end
          {order_id, cogs || 0}
        end)
      end

    # Get product_id for each order to group COGS by product
    orders_with_products =
      if Enum.empty?(all_orders) do
        []
      else
        from(o in Order,
          where: o.id in ^all_orders,
          select: {o.id, o.product_id}
        )
        |> Repo.all()
      end

    # Group COGS by product
    cogs_by_product =
      orders_with_products
      |> Enum.reduce(%{}, fn {order_id, product_id}, acc ->
        cogs_cents = Map.get(cogs_by_order, order_id, 0)
        Map.update(acc, product_id, cogs_cents, &(&1 + cogs_cents))
      end)

    # Combine revenue and COGS
    orders_by_product =
      orders_by_product_base
      |> Enum.map(fn product ->
        revenue_cents =
          if is_integer(product.revenue_cents),
            do: product.revenue_cents,
            else: Decimal.to_integer(product.revenue_cents)

        cogs_cents = Map.get(cogs_by_product, product.product_id, 0)
        gross_profit_cents = revenue_cents - cogs_cents

        product
        |> Map.put(:revenue_cents, revenue_cents)
        |> Map.put(:cogs_cents, cogs_cents)
        |> Map.put(:gross_profit_cents, gross_profit_cents)
      end)

    # --- Inventory position summary ---
    inventory_summary = inventory_position_summary()

    # --- Financial: full P&L for same period ---
    pnl = Accounting.profit_and_loss(start_date, end_date)

    %{
      total_orders: total_orders,
      delivered_orders: delivered_orders,
      orders_by_status: orders_by_status,
      orders_by_product: orders_by_product,
      revenue_cents: revenue_cents,
      avg_order_value_cents: avg_order_value_cents,
      inventory_summary: inventory_summary,
      pnl: pnl
    }
  end

  defp inventory_position_summary do
    # Get all stock items with quantity > 0
    stock_items = Inventory.list_stock_items()
    |> Enum.filter(fn stock -> stock.quantity_on_hand > 0 end)

    # Group by inventory type
    stock_by_type =
      stock_items
      |> Enum.group_by(fn stock ->
        Inventory.inventory_type(stock.ingredient.code)
      end)

    # Count items by type
    counts_by_type =
      Enum.map(stock_by_type, fn {type, items} ->
        total_value = Enum.reduce(items, 0, fn stock, acc ->
          acc + Inventory.inventory_item_value_cents(stock.ingredient_id, stock.location_id)
        end)
        {type, %{count: length(items), total_value_cents: total_value}}
      end)
      |> Enum.into(%{})

    # Get total inventory value
    total_value_cents = Inventory.total_inventory_value_cents()

    %{
      total_value_cents: total_value_cents,
      by_type: counts_by_type,
      total_items: length(stock_items)
    }
  end

  @doc """
  Calculate unit economics for a specific product.
  Returns revenue, COGS, gross margin, expenses, and net profit.
  """
  def unit_economics(product_id, start_date \\ nil, end_date \\ nil) do
    product = Repo.get!(Product, product_id)

    # Default to all time if no dates provided
    {start_date, end_date} =
      case {start_date, end_date} do
        {nil, nil} -> {~D[2000-01-01], Date.utc_today()}
        {s, e} when not is_nil(s) and not is_nil(e) -> {s, e}
        {s, nil} -> {s, Date.utc_today()}
        {nil, e} -> {~D[2000-01-01], e}
      end

    # Get all delivered orders for this product
    orders =
      from(o in Order,
        where:
          o.product_id == ^product_id and
            o.delivery_date >= ^start_date and
            o.delivery_date <= ^end_date and
            o.status == "delivered",
        preload: [:product]
      )
      |> Repo.all()

    # Calculate revenue from orders
    revenue_cents =
      Enum.reduce(orders, 0, fn order, acc ->
        base_revenue = order.product.price_cents || 0
        shipping_cents = if order.customer_paid_shipping, do: Accounting.shipping_fee_cents(), else: 0
        acc + base_revenue + shipping_cents
      end)

    # Calculate COGS from journal entries (ingredients used)
    # Sum COGS for all delivered orders of this product in the period
    order_ids = Enum.map(orders, & &1.id)

    cogs_cents =
      if Enum.empty?(order_ids) do
        0
      else
        # Build OR conditions for order references
        reference_patterns = Enum.map(order_ids, fn id -> "Order ##{id}" end)

        # Start with base query
        query =
          from(je in JournalEntry,
            join: jl in assoc(je, :journal_lines),
            join: acc in assoc(jl, :account),
            where:
              je.entry_type == "order_delivered" and
                acc.code == "5000" and
                je.date >= ^start_date and
                je.date <= ^end_date
          )

        # Use exact matching with IN clause instead of ilike patterns
        # ilike("Order #1") would wrongly match "Order #10", "Order #11", etc.
        query =
          query
          |> where([je], je.reference in ^reference_patterns)

        from([je, jl, acc] in query,
          select: sum(jl.debit_cents)
        )
        |> Repo.one()
        |> case do
          nil -> 0
          total -> total
        end
      end

    # Calculate gross margin
    gross_margin_cents = revenue_cents - cogs_cents
    gross_margin_percent =
      if revenue_cents > 0 do
        Float.round(gross_margin_cents / revenue_cents * 100, 2)
      else
        0.0
      end

    # Get total expenses for the period (all expenses, not allocated to product)
    total_expenses_cents =
      from(je in JournalEntry,
        join: jl in assoc(je, :journal_lines),
        join: acc in assoc(jl, :account),
        where:
          je.entry_type == "expense" and
            acc.type == "expense" and
            je.date >= ^start_date and
            je.date <= ^end_date,
        select: sum(jl.debit_cents)
      )
      |> Repo.one()
      |> case do
        nil -> 0
        total -> total
      end

    # Calculate number of units sold
    units_sold = length(orders)

    # Calculate per-unit metrics
    revenue_per_unit_cents = if units_sold > 0, do: div(revenue_cents, units_sold), else: 0
    cogs_per_unit_cents = if units_sold > 0, do: div(cogs_cents, units_sold), else: 0
    gross_margin_per_unit_cents = if units_sold > 0, do: div(gross_margin_cents, units_sold), else: 0

    # Allocate expenses proportionally based on revenue (optional - could be total or per unit)
    # For now, we'll show total expenses separately
    expenses_per_unit_cents = if units_sold > 0, do: div(total_expenses_cents, units_sold), else: 0

    # Net profit (revenue - COGS - expenses)
    net_profit_cents = gross_margin_cents - total_expenses_cents
    net_profit_per_unit_cents = if units_sold > 0, do: div(net_profit_cents, units_sold), else: 0
    net_margin_percent =
      if revenue_cents > 0 do
        Float.round(net_profit_cents / revenue_cents * 100, 2)
      else
        0.0
      end

    %{
      product: product,
      period: %{start_date: start_date, end_date: end_date},
      units_sold: units_sold,
      revenue_cents: revenue_cents,
      revenue_per_unit_cents: revenue_per_unit_cents,
      cogs_cents: cogs_cents,
      cogs_per_unit_cents: cogs_per_unit_cents,
      gross_margin_cents: gross_margin_cents,
      gross_margin_per_unit_cents: gross_margin_per_unit_cents,
      gross_margin_percent: gross_margin_percent,
      total_expenses_cents: total_expenses_cents,
      expenses_per_unit_cents: expenses_per_unit_cents,
      net_profit_cents: net_profit_cents,
      net_profit_per_unit_cents: net_profit_per_unit_cents,
      net_margin_percent: net_margin_percent
    }
  end

  @doc """
  Calculate unit economics for all active products.
  Returns a list of unit economics maps for each product.
  """
  def all_unit_economics(start_date \\ nil, end_date \\ nil) do
    # Default to all time if no dates provided
    {start_date, end_date} =
      case {start_date, end_date} do
        {nil, nil} -> {~D[2000-01-01], Date.utc_today()}
        {s, e} when not is_nil(s) and not is_nil(e) -> {s, e}
        {s, nil} -> {s, Date.utc_today()}
        {nil, e} -> {~D[2000-01-01], e}
      end

    # Get all active products
    products =
      from(p in Product,
        where: p.active == true,
        order_by: [asc: p.name]
      )
      |> Repo.all()

    # Calculate unit economics for each product
    products
    |> Enum.map(fn product ->
      unit_economics(product.id, start_date, end_date)
    end)
    |> Enum.filter(fn ue -> ue.units_sold > 0 end)
  end

  @doc """
  Calculate cash flow for a date range.
  Returns cash inflows, outflows, and net cash flow.
  """
  def cash_flow(start_date, end_date) do
    # Get all cash accounts
    cash_accounts =
      from(a in Accounting.Account,
        where: a.is_cash == true
      )
      |> Repo.all()

    cash_account_ids = Enum.map(cash_accounts, & &1.id)

    # Cash inflows (credits to cash accounts)
    cash_inflows_cents =
      from(je in JournalEntry,
        join: jl in assoc(je, :journal_lines),
        where:
          jl.account_id in ^cash_account_ids and
            jl.credit_cents > 0 and
            je.date >= ^start_date and
            je.date <= ^end_date,
        select: sum(jl.credit_cents)
      )
      |> Repo.one()
      |> case do
        nil -> 0
        total -> total
      end

    # Cash outflows (debits from cash accounts)
    cash_outflows_cents =
      from(je in JournalEntry,
        join: jl in assoc(je, :journal_lines),
        where:
          jl.account_id in ^cash_account_ids and
            jl.debit_cents > 0 and
            je.date >= ^start_date and
            je.date <= ^end_date,
        select: sum(jl.debit_cents)
      )
      |> Repo.one()
      |> case do
        nil -> 0
        total -> total
      end

    # Net cash flow
    net_cash_flow_cents = cash_inflows_cents - cash_outflows_cents

    # Break down by category
    # Inflows: sales, investments, etc.
    sales_inflows_cents =
      from(je in JournalEntry,
        join: jl in assoc(je, :journal_lines),
        where:
          jl.account_id in ^cash_account_ids and
            jl.credit_cents > 0 and
            je.entry_type in ["order_payment", "sale"] and
            je.date >= ^start_date and
            je.date <= ^end_date,
        select: sum(jl.credit_cents)
      )
      |> Repo.one()
      |> case do
        nil -> 0
        total -> total
      end

    investment_inflows_cents =
      from(je in JournalEntry,
        join: jl in assoc(je, :journal_lines),
        where:
          jl.account_id in ^cash_account_ids and
            jl.credit_cents > 0 and
            je.entry_type == "investment" and
            je.date >= ^start_date and
            je.date <= ^end_date,
        select: sum(jl.credit_cents)
      )
      |> Repo.one()
      |> case do
        nil -> 0
        total -> total
      end

    # Outflows: expenses, inventory purchases, withdrawals
    expense_outflows_cents =
      from(je in JournalEntry,
        join: jl in assoc(je, :journal_lines),
        where:
          jl.account_id in ^cash_account_ids and
            jl.debit_cents > 0 and
            je.entry_type in ["expense", "inventory_purchase"] and
            je.date >= ^start_date and
            je.date <= ^end_date,
        select: sum(jl.debit_cents)
      )
      |> Repo.one()
      |> case do
        nil -> 0
        total -> total
      end

    withdrawal_outflows_cents =
      from(je in JournalEntry,
        join: jl in assoc(je, :journal_lines),
        where:
          jl.account_id in ^cash_account_ids and
            jl.debit_cents > 0 and
            je.entry_type == "withdrawal" and
            je.date >= ^start_date and
            je.date <= ^end_date,
        select: sum(jl.debit_cents)
      )
      |> Repo.one()
      |> case do
        nil -> 0
        total -> total
      end

    %{
      period: %{start_date: start_date, end_date: end_date},
      cash_inflows_cents: cash_inflows_cents,
      cash_outflows_cents: cash_outflows_cents,
      net_cash_flow_cents: net_cash_flow_cents,
      breakdown: %{
        sales_inflows_cents: sales_inflows_cents,
        investment_inflows_cents: investment_inflows_cents,
        expense_outflows_cents: expense_outflows_cents,
        withdrawal_outflows_cents: withdrawal_outflows_cents,
        other_inflows_cents: cash_inflows_cents - sales_inflows_cents - investment_inflows_cents,
        other_outflows_cents: cash_outflows_cents - expense_outflows_cents - withdrawal_outflows_cents
      }
    }
  end
end
