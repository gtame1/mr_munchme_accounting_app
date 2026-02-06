defmodule MrMunchMeAccountingAppWeb.ApiController do
  @moduledoc """
  Simple REST API controller for querying data from the database.
  """
  use MrMunchMeAccountingAppWeb, :controller

  alias MrMunchMeAccountingApp.{Accounting, Customers, Inventory, Orders}

  # ---------- Products ----------

  def list_products(conn, _params) do
    products = Orders.list_all_products()

    json(conn, %{
      data: Enum.map(products, &serialize_product/1)
    })
  end

  def show_product(conn, %{"id" => id}) do
    product = Orders.get_product!(id)
    json(conn, %{data: serialize_product(product)})
  rescue
    Ecto.NoResultsError ->
      conn
      |> put_status(:not_found)
      |> json(%{error: "Product not found"})
  end

  # ---------- Orders ----------

  def list_orders(conn, params) do
    orders = Orders.list_orders(params)

    json(conn, %{
      data: Enum.map(orders, &serialize_order/1)
    })
  end

  def show_order(conn, %{"id" => id}) do
    order = Orders.get_order!(id)
    payment_summary = Orders.payment_summary(order)

    json(conn, %{
      data: serialize_order(order),
      payment_summary: %{
        product_total_cents: payment_summary.product_total_cents,
        shipping_cents: payment_summary.shipping_cents,
        order_total_cents: payment_summary.order_total_cents,
        total_paid_cents: payment_summary.total_paid_cents,
        outstanding_cents: payment_summary.outstanding_cents,
        fully_paid: payment_summary.fully_paid?,
        partially_paid: payment_summary.partially_paid?
      }
    })
  rescue
    Ecto.NoResultsError ->
      conn
      |> put_status(:not_found)
      |> json(%{error: "Order not found"})
  end

  # ---------- Customers ----------

  def list_customers(conn, _params) do
    customers = Customers.list_customers()

    json(conn, %{
      data: Enum.map(customers, &serialize_customer/1)
    })
  end

  def show_customer(conn, %{"id" => id}) do
    customer = Customers.get_customer!(id)
    json(conn, %{data: serialize_customer(customer)})
  rescue
    Ecto.NoResultsError ->
      conn
      |> put_status(:not_found)
      |> json(%{error: "Customer not found"})
  end

  def check_customer_phone(conn, %{"phone" => phone}) do
    case Customers.get_customer_by_phone(phone) do
      nil ->
        json(conn, %{exists: false})

      customer ->
        json(conn, %{exists: true, customer_name: customer.name, customer_id: customer.id})
    end
  end

  # ---------- Inventory ----------

  def list_ingredients(conn, _params) do
    ingredients = Inventory.list_ingredients()

    json(conn, %{
      data: Enum.map(ingredients, &serialize_ingredient/1)
    })
  end

  def show_ingredient(conn, %{"id" => id}) do
    ingredient = Inventory.get_ingredient!(id)
    json(conn, %{data: serialize_ingredient(ingredient)})
  rescue
    Ecto.NoResultsError ->
      conn
      |> put_status(:not_found)
      |> json(%{error: "Ingredient not found"})
  end

  def list_stock(conn, _params) do
    stock_items = Inventory.list_stock_items()

    json(conn, %{
      data: Enum.map(stock_items, &serialize_stock_item/1),
      total_value_cents: Inventory.total_inventory_value_cents()
    })
  end

  def list_locations(conn, _params) do
    locations = Inventory.list_locations()

    json(conn, %{
      data: Enum.map(locations, &serialize_location/1)
    })
  end

  # ---------- Accounting ----------

  def list_accounts(conn, _params) do
    accounts = Accounting.list_accounts()

    json(conn, %{
      data: Enum.map(accounts, &serialize_account/1)
    })
  end

  def show_account(conn, %{"id" => id}) do
    account = Accounting.get_account!(id)
    json(conn, %{data: serialize_account(account)})
  rescue
    Ecto.NoResultsError ->
      conn
      |> put_status(:not_found)
      |> json(%{error: "Account not found"})
  end

  def list_journal_entries(conn, _params) do
    entries = Accounting.list_journal_entries()

    json(conn, %{
      data: Enum.map(entries, &serialize_journal_entry/1)
    })
  end

  def show_journal_entry(conn, %{"id" => id}) do
    entry = Accounting.get_journal_entry!(id)
    json(conn, %{data: serialize_journal_entry(entry)})
  rescue
    Ecto.NoResultsError ->
      conn
      |> put_status(:not_found)
      |> json(%{error: "Journal entry not found"})
  end

  # ---------- Reports ----------

  def balance_sheet(conn, params) do
    as_of_date =
      case params["as_of_date"] do
        nil -> Date.utc_today()
        date_str ->
          case Date.from_iso8601(date_str) do
            {:ok, date} -> date
            _ -> Date.utc_today()
          end
      end

    report = Accounting.balance_sheet(as_of_date)

    json(conn, %{
      as_of_date: Date.to_iso8601(as_of_date),
      assets: Enum.map(report.assets, &serialize_balance_sheet_line/1),
      liabilities: Enum.map(report.liabilities, &serialize_balance_sheet_line/1),
      equity: Enum.map(report.equity, &serialize_balance_sheet_line/1),
      total_assets_cents: report.total_assets_cents,
      total_liabilities_cents: report.total_liabilities_cents,
      total_equity_cents: report.total_equity_cents,
      net_income_cents: report.net_income_cents,
      liabilities_plus_equity_plus_income_cents: report.liabilities_plus_equity_plus_income_cents,
      balance_diff_cents: report.balance_diff_cents
    })
  end

  def profit_and_loss(conn, params) do
    {start_date, end_date} = parse_date_range(params)

    report = Accounting.profit_and_loss(start_date, end_date)

    json(conn, %{
      start_date: Date.to_iso8601(start_date),
      end_date: Date.to_iso8601(end_date),
      total_revenue_cents: report.total_revenue_cents,
      total_cogs_cents: report.total_cogs_cents,
      gross_profit_cents: report.gross_profit_cents,
      total_opex_cents: report.total_opex_cents,
      operating_income_cents: report.operating_income_cents,
      net_income_cents: report.net_income_cents,
      gross_margin_percent: report.gross_margin_percent,
      operating_margin_percent: report.operating_margin_percent,
      net_margin_percent: report.net_margin_percent,
      revenue_accounts: Enum.map(report.revenue_accounts, &serialize_pnl_account/1),
      cogs_accounts: Enum.map(report.cogs_accounts, &serialize_pnl_account/1),
      operating_expense_accounts: Enum.map(report.operating_expense_accounts, &serialize_pnl_account/1)
    })
  end

  # ---------- Serializers ----------

  defp serialize_product(product) do
    %{
      id: product.id,
      name: product.name,
      sku: product.sku,
      price_cents: product.price_cents,
      active: product.active,
      inserted_at: product.inserted_at,
      updated_at: product.updated_at
    }
  end

  defp serialize_order(order) do
    %{
      id: order.id,
      customer_name: order.customer_name,
      customer_email: order.customer_email,
      customer_phone: order.customer_phone,
      delivery_type: order.delivery_type,
      delivery_address: order.delivery_address,
      delivery_date: order.delivery_date,
      delivery_time: order.delivery_time,
      status: order.status,
      customer_paid_shipping: order.customer_paid_shipping,
      product: order.product && serialize_product(order.product),
      customer_id: order.customer_id,
      prep_location_id: order.prep_location_id,
      inserted_at: order.inserted_at,
      updated_at: order.updated_at
    }
  end

  defp serialize_customer(customer) do
    %{
      id: customer.id,
      name: customer.name,
      email: customer.email,
      phone: customer.phone,
      delivery_address: customer.delivery_address,
      inserted_at: customer.inserted_at,
      updated_at: customer.updated_at
    }
  end

  defp serialize_ingredient(ingredient) do
    %{
      id: ingredient.id,
      code: ingredient.code,
      name: ingredient.name,
      unit: ingredient.unit,
      cost_per_unit_cents: ingredient.cost_per_unit_cents,
      inventory_type: ingredient.inventory_type,
      inserted_at: ingredient.inserted_at,
      updated_at: ingredient.updated_at
    }
  end

  defp serialize_stock_item(item) do
    %{
      id: item.id,
      ingredient: item.ingredient && %{
        id: item.ingredient.id,
        code: item.ingredient.code,
        name: item.ingredient.name,
        unit: item.ingredient.unit
      },
      location: item.location && %{
        id: item.location.id,
        code: item.location.code,
        name: item.location.name
      },
      quantity_on_hand: item.quantity_on_hand,
      avg_cost_per_unit_cents: item.avg_cost_per_unit_cents,
      value_cents: Inventory.inventory_item_value_cents(item.ingredient_id, item.location_id)
    }
  end

  defp serialize_location(location) do
    %{
      id: location.id,
      code: location.code,
      name: location.name,
      description: location.description
    }
  end

  defp serialize_account(account) do
    %{
      id: account.id,
      code: account.code,
      name: account.name,
      type: account.type,
      normal_balance: account.normal_balance,
      is_cash: account.is_cash
    }
  end

  defp serialize_journal_entry(entry) do
    %{
      id: entry.id,
      date: entry.date,
      entry_type: entry.entry_type,
      reference: entry.reference,
      description: entry.description,
      total_cents: Map.get(entry, :total_cents),
      journal_lines: Enum.map(entry.journal_lines || [], &serialize_journal_line/1),
      inserted_at: entry.inserted_at,
      updated_at: entry.updated_at
    }
  end

  defp serialize_journal_line(line) do
    %{
      id: line.id,
      account: line.account && serialize_account(line.account),
      debit_cents: line.debit_cents,
      credit_cents: line.credit_cents,
      description: line.description
    }
  end

  defp serialize_balance_sheet_line(line) do
    %{
      account: serialize_account(line.account),
      amount_cents: line.amount_cents
    }
  end

  defp serialize_pnl_account(account) do
    %{
      code: account.code,
      name: account.name,
      net_cents: account.net_cents
    }
  end

  # ---------- Helpers ----------

  defp parse_date_range(params) do
    today = Date.utc_today()

    start_date =
      case params["start_date"] do
        nil -> Date.beginning_of_month(today)
        date_str ->
          case Date.from_iso8601(date_str) do
            {:ok, date} -> date
            _ -> Date.beginning_of_month(today)
          end
      end

    end_date =
      case params["end_date"] do
        nil -> today
        date_str ->
          case Date.from_iso8601(date_str) do
            {:ok, date} -> date
            _ -> today
          end
      end

    {start_date, end_date}
  end
end
