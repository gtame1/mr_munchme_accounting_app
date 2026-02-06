defmodule MrMunchMeAccountingApp.ReportingTest do
  use MrMunchMeAccountingApp.DataCase, async: true

  alias MrMunchMeAccountingApp.{Reporting, Repo}
  alias MrMunchMeAccountingApp.Orders.Order

  import MrMunchMeAccountingApp.OrdersFixtures
  import MrMunchMeAccountingApp.AccountingFixtures

  describe "unit_economics/3" do
    setup do
      accounts = standard_accounts_fixture()
      product = product_fixture(%{price_cents: 15000, name: "Test Product"})
      location = location_fixture()

      {:ok, accounts: accounts, product: product, location: location}
    end

    test "returns metrics for product with no orders", %{product: product} do
      today = Date.utc_today()
      result = Reporting.unit_economics(product.id, today, today)

      assert result.product.id == product.id
      assert result.units_sold == 0
      assert result.revenue_cents == 0
      assert result.cogs_cents == 0
    end

    test "calculates revenue for delivered orders", %{product: product, location: location} do
      today = Date.utc_today()

      # Create a delivered order
      _order = order_fixture(%{product: product, location: location, status: "delivered"})

      result = Reporting.unit_economics(product.id, today, today)

      assert result.units_sold == 1
      assert result.revenue_cents == product.price_cents
      assert result.revenue_per_unit_cents == product.price_cents
    end

    test "includes shipping revenue when customer_paid_shipping is true", %{product: product, location: location} do
      # Create shipping product
      _shipping = product_fixture(%{sku: "ENVIO", name: "Shipping", price_cents: 5000})

      today = Date.utc_today()

      # Create order with shipping
      {:ok, _order} =
        %Order{}
        |> Order.changeset(%{
          customer_name: "Test",
          customer_phone: "5551234567",
          product_id: product.id,
          prep_location_id: location.id,
          delivery_date: today,
          delivery_type: "delivery",
          status: "delivered",
          customer_paid_shipping: true
        })
        |> Repo.insert()

      result = Reporting.unit_economics(product.id, today, today)

      assert result.units_sold == 1
      # Revenue should be product + shipping
      assert result.revenue_cents == product.price_cents + 5000
    end

    test "excludes non-delivered orders from calculations", %{product: product, location: location} do
      today = Date.utc_today()

      # Create orders with different statuses
      _new_order = order_fixture(%{product: product, location: location, status: "new_order"})
      _in_prep = order_fixture(%{product: product, location: location, status: "in_prep"})
      _delivered = order_fixture(%{product: product, location: location, status: "delivered"})
      _canceled = order_fixture(%{product: product, location: location, status: "canceled"})

      result = Reporting.unit_economics(product.id, today, today)

      # Only the delivered order should count
      assert result.units_sold == 1
    end

    test "filters by date range", %{product: product, location: location} do
      today = Date.utc_today()
      yesterday = Date.add(today, -1)
      _tomorrow = Date.add(today, 1)

      # Create orders on different dates
      _yesterday_order = order_fixture(%{product: product, location: location, status: "delivered", delivery_date: yesterday})
      _today_order = order_fixture(%{product: product, location: location, status: "delivered", delivery_date: today})

      # Query only today
      result = Reporting.unit_economics(product.id, today, today)
      assert result.units_sold == 1

      # Query both days
      result_both = Reporting.unit_economics(product.id, yesterday, today)
      assert result_both.units_sold == 2
    end

    test "calculates gross margin correctly", %{product: product, location: location} do
      today = Date.utc_today()

      _order = order_fixture(%{product: product, location: location, status: "delivered"})

      result = Reporting.unit_economics(product.id, today, today)

      # With no COGS recorded, gross margin should equal revenue
      assert result.gross_margin_cents == result.revenue_cents - result.cogs_cents
    end

    test "defaults to all time when no dates provided", %{product: product, location: location} do
      # Create an order with today's date
      _order = order_fixture(%{product: product, location: location, status: "delivered"})

      result = Reporting.unit_economics(product.id, nil, nil)

      assert result.units_sold == 1
      assert result.period.start_date == ~D[2000-01-01]
    end
  end

  describe "cash_flow/2" do
    setup do
      accounts = standard_accounts_fixture()
      {:ok, accounts: accounts}
    end

    test "returns zero values when no cash transactions", %{accounts: _accounts} do
      today = Date.utc_today()
      result = Reporting.cash_flow(today, today)

      assert result.cash_inflows_cents == 0
      assert result.cash_outflows_cents == 0
      assert result.net_cash_flow_cents == 0
    end

    test "includes period in result", %{accounts: _accounts} do
      today = Date.utc_today()
      yesterday = Date.add(today, -1)

      result = Reporting.cash_flow(yesterday, today)

      assert result.period.start_date == yesterday
      assert result.period.end_date == today
    end
  end

  describe "dashboard_metrics/2" do
    setup do
      accounts = standard_accounts_fixture()
      product = product_fixture(%{price_cents: 10000})
      location = location_fixture()

      {:ok, accounts: accounts, product: product, location: location}
    end

    test "returns order counts by status", %{product: product, location: location} do
      today = Date.utc_today()

      _order1 = order_fixture(%{product: product, location: location, status: "new_order"})
      _order2 = order_fixture(%{product: product, location: location, status: "delivered"})

      result = Reporting.dashboard_metrics(today, today)

      assert result.total_orders == 2
      assert result.delivered_orders == 1
    end

    test "calculates revenue from all non-canceled orders", %{product: product, location: location} do
      today = Date.utc_today()

      _order1 = order_fixture(%{product: product, location: location, status: "delivered"})
      _order2 = order_fixture(%{product: product, location: location, status: "new_order"})

      result = Reporting.dashboard_metrics(today, today)

      # Both orders count for revenue (all non-canceled)
      assert result.revenue_cents == product.price_cents * 2
    end

    test "groups orders by product", %{location: location} do
      today = Date.utc_today()

      product1 = product_fixture(%{price_cents: 10000, name: "Product A"})
      product2 = product_fixture(%{price_cents: 20000, name: "Product B"})

      _order1 = order_fixture(%{product: product1, location: location, status: "delivered"})
      _order2 = order_fixture(%{product: product1, location: location, status: "delivered"})
      _order3 = order_fixture(%{product: product2, location: location, status: "delivered"})

      result = Reporting.dashboard_metrics(today, today)

      assert length(result.orders_by_product) == 2

      product1_stats = Enum.find(result.orders_by_product, fn p -> p.product_id == product1.id end)
      assert product1_stats.order_count == 2
      assert product1_stats.revenue_cents == 20000

      product2_stats = Enum.find(result.orders_by_product, fn p -> p.product_id == product2.id end)
      assert product2_stats.order_count == 1
      assert product2_stats.revenue_cents == 20000
    end

    test "filters by date range", %{product: product, location: location} do
      today = Date.utc_today()
      yesterday = Date.add(today, -1)

      _yesterday_order = order_fixture(%{product: product, location: location, status: "delivered", delivery_date: yesterday})
      _today_order = order_fixture(%{product: product, location: location, status: "delivered", delivery_date: today})

      # Query only today
      result = Reporting.dashboard_metrics(today, today)
      assert result.total_orders == 1
      assert result.delivered_orders == 1

      # Query both days
      result_both = Reporting.dashboard_metrics(yesterday, today)
      assert result_both.total_orders == 2
    end

    test "calculates average order value", %{product: product, location: location} do
      today = Date.utc_today()

      _order1 = order_fixture(%{product: product, location: location, status: "delivered"})
      _order2 = order_fixture(%{product: product, location: location, status: "delivered"})

      result = Reporting.dashboard_metrics(today, today)

      assert result.delivered_orders == 2
      assert result.avg_order_value_cents == product.price_cents
    end

    test "calculates avg order value from all non-canceled orders", %{product: product, location: location} do
      today = Date.utc_today()

      _order = order_fixture(%{product: product, location: location, status: "new_order"})

      result = Reporting.dashboard_metrics(today, today)

      # avg_order_value is based on all non-canceled orders
      assert result.delivered_orders == 0
      assert result.total_orders == 1
      assert result.avg_order_value_cents == product.price_cents
    end
  end
end
