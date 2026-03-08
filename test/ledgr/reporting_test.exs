defmodule Ledgr.Core.ReportingTest do
  use Ledgr.DataCase, async: true

  alias Ledgr.Core.Reporting
  alias Ledgr.Domains.MrMunchMe.Reporting, as: DomainReporting
  alias Ledgr.Repo
  alias Ledgr.Domains.MrMunchMe.Orders.Order

  import Ledgr.Domains.MrMunchMe.OrdersFixtures
  import Ledgr.Core.AccountingFixtures

  describe "unit_economics/3" do
    setup do
      accounts = standard_accounts_fixture()
      product = product_fixture(%{name: "Test Product"})
      variant = variant_fixture(%{product: product, price_cents: 15000})
      location = location_fixture()

      {:ok, accounts: accounts, product: product, variant: variant, location: location}
    end

    test "returns metrics for product with no orders", %{product: product} do
      today = Date.utc_today()
      result = DomainReporting.unit_economics(product.id, today, today)

      assert result.product.id == product.id
      assert result.units_sold == 0
      assert result.revenue_cents == 0
      assert result.cogs_cents == 0
    end

    test "calculates revenue for delivered orders", %{product: product, variant: variant, location: location} do
      today = Date.utc_today()

      # Create a delivered order
      _order = order_fixture(%{variant: variant, location: location, status: "delivered"})

      result = DomainReporting.unit_economics(product.id, today, today)

      assert result.units_sold == 1
      assert result.revenue_cents == variant.price_cents
      assert result.revenue_per_unit_cents == variant.price_cents
    end

    test "includes shipping revenue when customer_paid_shipping is true", %{product: product, variant: variant, location: location} do
      # Create shipping variant
      envio_product = product_fixture(%{name: "Shipping"})
      _envio_variant = variant_fixture(%{product: envio_product, sku: "ENVIO", price_cents: 5000})

      today = Date.utc_today()

      # Create order with shipping
      {:ok, _order} =
        %Order{}
        |> Order.changeset(%{
          customer_name: "Test",
          customer_phone: "5551234567",
          variant_id: variant.id,
          prep_location_id: location.id,
          delivery_date: today,
          delivery_type: "delivery",
          status: "delivered",
          customer_paid_shipping: true
        })
        |> Repo.insert()

      result = DomainReporting.unit_economics(product.id, today, today)

      assert result.units_sold == 1
      # Revenue should be product variant price + shipping
      assert result.revenue_cents == variant.price_cents + 5000
    end

    test "excludes non-delivered orders from calculations", %{product: product, variant: variant, location: location} do
      today = Date.utc_today()

      # Create orders with different statuses
      _new_order = order_fixture(%{variant: variant, location: location, status: "new_order"})
      _in_prep = order_fixture(%{variant: variant, location: location, status: "in_prep"})
      _delivered = order_fixture(%{variant: variant, location: location, status: "delivered"})
      _canceled = order_fixture(%{variant: variant, location: location, status: "canceled"})

      result = DomainReporting.unit_economics(product.id, today, today)

      # Only the delivered order should count
      assert result.units_sold == 1
    end

    test "filters by date range", %{product: product, variant: variant, location: location} do
      today = Date.utc_today()
      yesterday = Date.add(today, -1)
      _tomorrow = Date.add(today, 1)

      # Create orders on different dates
      _yesterday_order = order_fixture(%{variant: variant, location: location, status: "delivered", delivery_date: yesterday})
      _today_order = order_fixture(%{variant: variant, location: location, status: "delivered", delivery_date: today})

      # Query only today
      result = DomainReporting.unit_economics(product.id, today, today)
      assert result.units_sold == 1

      # Query both days
      result_both = DomainReporting.unit_economics(product.id, yesterday, today)
      assert result_both.units_sold == 2
    end

    test "calculates gross margin correctly", %{product: product, variant: variant, location: location} do
      today = Date.utc_today()

      _order = order_fixture(%{variant: variant, location: location, status: "delivered"})

      result = DomainReporting.unit_economics(product.id, today, today)

      # With no COGS recorded, gross margin should equal revenue
      assert result.gross_margin_cents == result.revenue_cents - result.cogs_cents
    end

    test "defaults to all time when no dates provided", %{product: product, variant: variant, location: location} do
      # Create an order with today's date
      _order = order_fixture(%{variant: variant, location: location, status: "delivered"})

      result = DomainReporting.unit_economics(product.id, nil, nil)

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
      product = product_fixture()
      variant = variant_fixture(%{product: product, price_cents: 10000})
      location = location_fixture()

      {:ok, accounts: accounts, product: product, variant: variant, location: location}
    end

    test "returns order counts by status", %{variant: variant, location: location} do
      today = Date.utc_today()

      _order1 = order_fixture(%{variant: variant, location: location, status: "new_order"})
      _order2 = order_fixture(%{variant: variant, location: location, status: "delivered"})

      result = DomainReporting.dashboard_metrics(today, today)

      assert result.total_orders == 2
      assert result.delivered_orders == 1
    end

    test "calculates revenue from all non-canceled orders", %{variant: variant, location: location} do
      today = Date.utc_today()

      _order1 = order_fixture(%{variant: variant, location: location, status: "delivered"})
      _order2 = order_fixture(%{variant: variant, location: location, status: "new_order"})

      result = DomainReporting.dashboard_metrics(today, today)

      # Both orders count for revenue (all non-canceled)
      assert result.revenue_cents == variant.price_cents * 2
    end

    test "groups orders by product", %{location: location} do
      today = Date.utc_today()

      product1 = product_fixture(%{name: "Product A"})
      variant1 = variant_fixture(%{product: product1, price_cents: 10000})
      product2 = product_fixture(%{name: "Product B"})
      variant2 = variant_fixture(%{product: product2, price_cents: 20000})

      _order1 = order_fixture(%{variant: variant1, location: location, status: "delivered"})
      _order2 = order_fixture(%{variant: variant1, location: location, status: "delivered"})
      _order3 = order_fixture(%{variant: variant2, location: location, status: "delivered"})

      result = DomainReporting.dashboard_metrics(today, today)

      assert length(result.orders_by_product) == 2

      product1_stats = Enum.find(result.orders_by_product, fn p -> p.product_id == product1.id end)
      assert product1_stats.order_count == 2
      assert product1_stats.revenue_cents == 20000

      product2_stats = Enum.find(result.orders_by_product, fn p -> p.product_id == product2.id end)
      assert product2_stats.order_count == 1
      assert product2_stats.revenue_cents == 20000
    end

    test "filters by date range", %{variant: variant, location: location} do
      today = Date.utc_today()
      yesterday = Date.add(today, -1)

      _yesterday_order = order_fixture(%{variant: variant, location: location, status: "delivered", delivery_date: yesterday})
      _today_order = order_fixture(%{variant: variant, location: location, status: "delivered", delivery_date: today})

      # Query only today
      result = DomainReporting.dashboard_metrics(today, today)
      assert result.total_orders == 1
      assert result.delivered_orders == 1

      # Query both days
      result_both = DomainReporting.dashboard_metrics(yesterday, today)
      assert result_both.total_orders == 2
    end

    test "calculates average order value", %{variant: variant, location: location} do
      today = Date.utc_today()

      _order1 = order_fixture(%{variant: variant, location: location, status: "delivered"})
      _order2 = order_fixture(%{variant: variant, location: location, status: "delivered"})

      result = DomainReporting.dashboard_metrics(today, today)

      assert result.delivered_orders == 2
      assert result.avg_order_value_cents == variant.price_cents
    end

    test "calculates avg order value from all non-canceled orders", %{variant: variant, location: location} do
      today = Date.utc_today()

      _order = order_fixture(%{variant: variant, location: location, status: "new_order"})

      result = DomainReporting.dashboard_metrics(today, today)

      # avg_order_value is based on all non-canceled orders
      assert result.delivered_orders == 0
      assert result.total_orders == 1
      assert result.avg_order_value_cents == variant.price_cents
    end
  end

  # ---------------------------------------------------------------------------
  # AR aging report
  # ---------------------------------------------------------------------------

  describe "ar_aging_report/1" do
    setup do
      accounts = standard_accounts_fixture()
      product = product_fixture()
      variant = variant_fixture(%{product: product, price_cents: 10000})
      location = location_fixture()

      {:ok, accounts: accounts, variant: variant, location: location}
    end

    test "returns empty result when no delivered orders exist" do
      today = Date.utc_today()
      result = DomainReporting.ar_aging_report(today)

      assert result.as_of_date == today
      assert result.total_outstanding_cents == 0
      assert result.line_items == []
      assert result.buckets == %{current: 0, days_31_60: 0, days_61_90: 0, over_90: 0}
    end

    test "includes unpaid delivered order in current bucket when as_of_date equals delivery_date",
         %{variant: variant, location: location} do
      today = Date.utc_today()
      order = order_fixture(%{variant: variant, location: location, status: "delivered", delivery_date: today})

      result = DomainReporting.ar_aging_report(today)

      assert result.total_outstanding_cents == 10000
      assert result.buckets.current == 10000
      assert length(result.line_items) == 1

      item = hd(result.line_items)
      assert item.order_id == order.id
      assert item.outstanding_cents == 10000
      assert item.paid_cents == 0
      assert item.order_total_cents == 10000
      assert item.bucket == "current"
      assert item.days_outstanding == 0
    end

    test "excludes fully paid delivered order from line items",
         %{accounts: accounts, variant: variant, location: location} do
      today = Date.utc_today()
      order = order_fixture(%{variant: variant, location: location, status: "delivered", delivery_date: today})
      _payment = order_payment_fixture(order, accounts["1000"], %{"amount_cents" => 10000})

      result = DomainReporting.ar_aging_report(today)

      assert result.total_outstanding_cents == 0
      assert result.line_items == []
    end

    test "shows outstanding balance for partially paid order",
         %{accounts: accounts, variant: variant, location: location} do
      today = Date.utc_today()
      order = order_fixture(%{variant: variant, location: location, status: "delivered", delivery_date: today})
      _payment = order_payment_fixture(order, accounts["1000"], %{"amount_cents" => 3000})

      result = DomainReporting.ar_aging_report(today)

      assert result.total_outstanding_cents == 7000

      item = hd(result.line_items)
      assert item.outstanding_cents == 7000
      assert item.paid_cents == 3000
      assert item.order_total_cents == 10000
    end

    test "places orders into correct aging buckets based on days since delivery",
         %{variant: variant, location: location} do
      as_of = Date.utc_today()

      # current: ≤ 30 days — 15 days ago
      _c = order_fixture(%{variant: variant, location: location, status: "delivered", delivery_date: Date.add(as_of, -15)})
      # 31-60 days — 45 days ago
      _a = order_fixture(%{variant: variant, location: location, status: "delivered", delivery_date: Date.add(as_of, -45)})
      # 61-90 days — 75 days ago
      _b = order_fixture(%{variant: variant, location: location, status: "delivered", delivery_date: Date.add(as_of, -75)})
      # 90+ days — 100 days ago
      _d = order_fixture(%{variant: variant, location: location, status: "delivered", delivery_date: Date.add(as_of, -100)})

      result = DomainReporting.ar_aging_report(as_of)

      assert result.buckets.current == 10000
      assert result.buckets.days_31_60 == 10000
      assert result.buckets.days_61_90 == 10000
      assert result.buckets.over_90 == 10000
      assert result.total_outstanding_cents == 40000
      assert length(result.line_items) == 4
    end

    test "excludes non-delivered orders (new_order, in_prep, canceled)",
         %{variant: variant, location: location} do
      today = Date.utc_today()
      _new = order_fixture(%{variant: variant, location: location, status: "new_order", delivery_date: today})
      _in_prep = order_fixture(%{variant: variant, location: location, status: "in_prep", delivery_date: today})
      _canceled = order_fixture(%{variant: variant, location: location, status: "canceled", delivery_date: today})

      result = DomainReporting.ar_aging_report(today)

      assert result.line_items == []
      assert result.total_outstanding_cents == 0
    end

    test "uses actual_delivery_date over delivery_date for aging calculation",
         %{variant: variant, location: location} do
      as_of = Date.utc_today()
      # delivery_date alone would put this in "current" (5 days ago)
      delivery_date = Date.add(as_of, -5)
      # but actual_delivery_date pushes it into "31-60" (45 days ago)
      actual_delivery_date = Date.add(as_of, -45)

      _order = order_fixture(%{
        variant: variant,
        location: location,
        status: "delivered",
        delivery_date: delivery_date,
        actual_delivery_date: actual_delivery_date
      })

      result = DomainReporting.ar_aging_report(as_of)

      # Should use actual_delivery_date — 45 days → "31-60" bucket
      assert result.buckets.current == 0
      assert result.buckets.days_31_60 == 10000

      item = hd(result.line_items)
      assert item.days_outstanding == 45
      assert item.bucket == "31-60"
    end
  end
end
