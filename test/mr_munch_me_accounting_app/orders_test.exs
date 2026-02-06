defmodule MrMunchMeAccountingApp.OrdersTest do
  use MrMunchMeAccountingApp.DataCase, async: true

  alias MrMunchMeAccountingApp.{Orders, Repo}
  alias MrMunchMeAccountingApp.Orders.{Order, Product}

  import MrMunchMeAccountingApp.OrdersFixtures
  import MrMunchMeAccountingApp.AccountingFixtures
  import MrMunchMeAccountingApp.CustomersFixtures

  describe "products" do
    test "list_products/0 returns only active products" do
      product1 = product_fixture(%{name: "Active Product", active: true})
      _product2 = product_fixture(%{name: "Inactive Product", active: false})

      products = Orders.list_products()
      assert length(products) == 1
      assert hd(products).id == product1.id
    end

    test "list_all_products/0 returns all products including inactive" do
      _product1 = product_fixture(%{name: "Active Product", active: true})
      _product2 = product_fixture(%{name: "Inactive Product", active: false})

      products = Orders.list_all_products()
      assert length(products) == 2
    end

    test "get_product!/1 returns the product with given id" do
      product = product_fixture()
      assert Orders.get_product!(product.id).id == product.id
    end

    test "create_product/1 with valid data creates a product" do
      attrs = %{sku: "NEW-SKU", name: "New Product", price_cents: 5000, active: true}
      assert {:ok, %Product{} = product} = Orders.create_product(attrs)
      assert product.sku == "NEW-SKU"
      assert product.name == "New Product"
      assert product.price_cents == 5000
    end

    test "create_product/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Orders.create_product(%{})
    end

    test "update_product/2 with valid data updates the product" do
      product = product_fixture()
      assert {:ok, %Product{} = updated} = Orders.update_product(product, %{name: "Updated Name"})
      assert updated.name == "Updated Name"
    end

    test "product_select_options/0 returns formatted options" do
      product = product_fixture(%{name: "Test Product"})
      options = Orders.product_select_options()

      assert Enum.any?(options, fn {name, id} ->
        id == product.id && String.contains?(name, "Test Product")
      end)
    end
  end

  describe "create_order/1" do
    setup do
      accounts = standard_accounts_fixture()
      product = product_fixture(%{price_cents: 15000})
      location = location_fixture()

      {:ok, accounts: accounts, product: product, location: location}
    end

    test "creates order with valid data", %{product: product, location: location} do
      attrs = %{
        "customer_name" => "John Doe",
        "customer_phone" => "5551234567",
        "product_id" => to_string(product.id),
        "prep_location_id" => to_string(location.id),
        "delivery_date" => Date.to_iso8601(Date.utc_today()),
        "delivery_type" => "delivery",
        "delivery_address" => "123 Main St"
      }

      assert {:ok, %Order{} = order} = Orders.create_order(attrs)
      assert order.customer_name == "John Doe"
      assert order.customer_phone == "5551234567"
      assert order.status == "new_order"
      assert order.delivery_type == "delivery"
    end

    test "rejects new customer with existing phone, prompting to use existing customer list", %{product: product, location: location} do
      # Create a customer first
      _customer = customer_fixture(%{phone: "5559876543", name: "Existing Customer", email: "existing@test.com"})

      attrs = %{
        "customer_name" => "Different Name",
        "customer_phone" => "5559876543",
        "customer_email" => "different@test.com",
        "product_id" => to_string(product.id),
        "prep_location_id" => to_string(location.id),
        "delivery_date" => Date.to_iso8601(Date.utc_today()),
        "delivery_type" => "pickup"
      }

      assert {:error, %Ecto.Changeset{} = changeset} = Orders.create_order(attrs)
      errors = errors_on(changeset)
      assert [msg] = errors[:customer_phone]
      assert msg =~ "already belongs to Existing Customer"
      assert msg =~ "existing customer list"
    end

    test "creates order with customer_id directly, syncing customer fields", %{product: product, location: location} do
      customer = customer_fixture(%{phone: "5551111111", name: "Real Name", email: "real@test.com"})

      attrs = %{
        "customer_id" => to_string(customer.id),
        "customer_name" => "Wrong Name",
        "customer_phone" => "0000000000",
        "product_id" => to_string(product.id),
        "prep_location_id" => to_string(location.id),
        "delivery_date" => Date.to_iso8601(Date.utc_today()),
        "delivery_type" => "pickup"
      }

      assert {:ok, %Order{} = order} = Orders.create_order(attrs)
      assert order.customer_id == customer.id
      # Denormalized fields should come from the customer record
      assert order.customer_name == "Real Name"
      assert order.customer_phone == "5551111111"
      assert order.customer_email == "real@test.com"
    end

    test "creates order with shipping", %{product: product, location: location} do
      attrs = %{
        "customer_name" => "Shipping Customer",
        "customer_phone" => "5552222222",
        "product_id" => to_string(product.id),
        "prep_location_id" => to_string(location.id),
        "delivery_date" => Date.to_iso8601(Date.utc_today()),
        "delivery_type" => "delivery",
        "customer_paid_shipping" => "true"
      }

      assert {:ok, %Order{} = order} = Orders.create_order(attrs)
      assert order.customer_paid_shipping == true
    end

    test "fails with missing required fields", %{product: product} do
      attrs = %{
        "customer_name" => "Test",
        "product_id" => to_string(product.id)
        # Missing prep_location_id, delivery_date, etc.
      }

      assert {:error, _changeset} = Orders.create_order(attrs)
    end
  end

  describe "order_total_cents/1" do
    setup do
      _accounts = standard_accounts_fixture()
      {:ok, %{}}
    end

    test "returns tuple with product price and zero shipping for pickup order" do
      product = product_fixture(%{price_cents: 12000})
      order = order_fixture(%{product: product, delivery_type: "pickup", customer_paid_shipping: false})

      assert {12000, 0} = Orders.order_total_cents(order)
    end

    test "includes shipping in tuple for delivery order with customer_paid_shipping" do
      # Create the shipping product required by Accounting.shipping_fee_cents()
      _shipping_product = product_fixture(%{sku: "ENVIO", name: "Shipping", price_cents: 5000})

      product = product_fixture(%{price_cents: 12000})
      location = location_fixture()

      # Create order directly with customer_paid_shipping set
      {:ok, order} =
        %Order{}
        |> Order.changeset(%{
          customer_name: "Test",
          customer_phone: "5551234567",
          product_id: product.id,
          prep_location_id: location.id,
          delivery_date: Date.utc_today(),
          delivery_type: "delivery",
          status: "new_order",
          customer_paid_shipping: true
        })
        |> Repo.insert()

      # Reload order from database to ensure customer_paid_shipping is persisted
      order = Orders.get_order!(order.id)
      assert order.customer_paid_shipping == true

      {product_total, shipping} = Orders.order_total_cents(order)
      assert product_total == 12000
      assert shipping == 5000
    end

    test "returns zero shipping for delivery without customer_paid_shipping" do
      product = product_fixture(%{price_cents: 12000})
      order = order_fixture(%{product: product, delivery_type: "delivery", customer_paid_shipping: false})

      assert {12000, 0} = Orders.order_total_cents(order)
    end
  end

  describe "payment_summary/1" do
    setup do
      accounts = standard_accounts_fixture()
      product = product_fixture(%{price_cents: 10000})
      location = location_fixture()
      order = order_fixture(%{product: product, location: location})

      {:ok, accounts: accounts, order: order, cash_account: accounts["1000"]}
    end

    test "returns zero payments for order with no payments", %{order: order} do
      summary = Orders.payment_summary(order)

      assert summary.total_paid_cents == 0
      assert summary.outstanding_cents > 0
      assert summary.fully_paid? == false
      assert summary.partially_paid? == false
    end

    test "calculates partial payment correctly", %{order: order, cash_account: cash_account} do
      # Pay 5000 of 10000
      _payment = order_payment_fixture(order, cash_account, %{"amount_cents" => 5000})

      order = Orders.get_order!(order.id)
      summary = Orders.payment_summary(order)

      assert summary.total_paid_cents == 5000
      assert summary.outstanding_cents == 5000
      assert summary.fully_paid? == false
      assert summary.partially_paid? == true
    end

    test "marks as fully paid when total is covered", %{order: order, cash_account: cash_account} do
      # Pay full amount
      _payment = order_payment_fixture(order, cash_account, %{"amount_cents" => 10000})

      order = Orders.get_order!(order.id)
      summary = Orders.payment_summary(order)

      assert summary.total_paid_cents == 10000
      assert summary.outstanding_cents == 0
      assert summary.fully_paid? == true
    end

    test "handles multiple payments", %{order: order, cash_account: cash_account} do
      _payment1 = order_payment_fixture(order, cash_account, %{"amount_cents" => 3000})
      _payment2 = order_payment_fixture(order, cash_account, %{"amount_cents" => 7000})

      order = Orders.get_order!(order.id)
      summary = Orders.payment_summary(order)

      assert summary.total_paid_cents == 10000
      assert summary.fully_paid? == true
    end
  end

  describe "update_order_status/2" do
    # Note: Full status transition tests with inventory consumption
    # are in inventory_movement_accounting_test.exs
    # These tests focus on simpler transitions that don't require full recipe setup

    setup do
      accounts = standard_accounts_fixture()
      product = product_fixture(%{price_cents: 10000})
      location = location_fixture()

      {:ok, accounts: accounts, product: product, location: location}
    end

    test "transitions from in_prep to ready", %{product: product, location: location} do
      order = order_fixture(%{product: product, location: location, status: "in_prep"})

      assert {:ok, updated_order} = Orders.update_order_status(order, "ready")
      assert updated_order.status == "ready"
    end

    test "transitions from ready to delivered", %{product: product, location: location} do
      order = order_fixture(%{product: product, location: location, status: "ready"})

      assert {:ok, updated_order} = Orders.update_order_status(order, "delivered")
      assert updated_order.status == "delivered"
    end

    test "can cancel from new_order status", %{product: product, location: location} do
      order = order_fixture(%{product: product, location: location, status: "new_order"})

      assert {:ok, updated_order} = Orders.update_order_status(order, "canceled")
      assert updated_order.status == "canceled"
    end

    test "can cancel from ready status", %{product: product, location: location} do
      order = order_fixture(%{product: product, location: location, status: "ready"})

      assert {:ok, updated_order} = Orders.update_order_status(order, "canceled")
      assert updated_order.status == "canceled"
    end
  end

  describe "list_orders/1" do
    setup do
      _accounts = standard_accounts_fixture()
      product = product_fixture()
      location = location_fixture()

      order1 = order_fixture(%{product: product, location: location, status: "new_order"})
      order2 = order_fixture(%{product: product, location: location, status: "delivered"})
      order3 = order_fixture(%{product: product, location: location, status: "canceled"})

      {:ok, orders: [order1, order2, order3], product: product, non_canceled: [order1, order2]}
    end

    test "excludes canceled orders by default", %{non_canceled: non_canceled} do
      result = Orders.list_orders()
      # Should only return non-canceled orders
      assert length(result) >= length(non_canceled)
      assert Enum.all?(result, fn o -> o.status != "canceled" end)
    end

    test "filters by status", %{orders: [order1 | _]} do
      result = Orders.list_orders(%{"status" => "new_order"})

      assert Enum.any?(result, fn o -> o.id == order1.id end)
      assert Enum.all?(result, fn o -> o.status == "new_order" end)
    end

    test "filters by product_id", %{product: product} do
      result = Orders.list_orders(%{"product_id" => to_string(product.id)})

      assert Enum.all?(result, fn o -> o.product_id == product.id end)
    end

    test "filters by date range" do
      today = Date.utc_today()
      yesterday = Date.add(today, -1)
      tomorrow = Date.add(today, 1)

      result = Orders.list_orders(%{
        "date_from" => Date.to_iso8601(yesterday),
        "date_to" => Date.to_iso8601(tomorrow)
      })

      assert Enum.all?(result, fn o ->
        o.delivery_date >= yesterday and o.delivery_date <= tomorrow
      end)
    end
  end
end
