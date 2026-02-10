defmodule Ledgr.OrdersFixtures do
  @moduledoc """
  Test helpers for creating entities via the `Ledgr.Orders` context.
  """

  alias Ledgr.{Orders, Repo}
  alias Ledgr.Orders.{Product, Order}
  alias Ledgr.Inventory.Location

  @doc """
  Generate a product.
  """
  def product_fixture(attrs \\ %{}) do
    {:ok, product} =
      %Product{}
      |> Product.changeset(
        Enum.into(attrs, %{
          sku: "TEST-#{System.unique_integer([:positive])}",
          name: "Test Product",
          price_cents: 10000,
          active: true
        })
      )
      |> Repo.insert()

    product
  end

  @doc """
  Generate a location for order prep.
  """
  def location_fixture(attrs \\ %{}) do
    {:ok, location} =
      %Location{}
      |> Location.changeset(
        Enum.into(attrs, %{
          code: "LOC_#{System.unique_integer([:positive])}",
          name: "Test Location"
        })
      )
      |> Repo.insert()

    location
  end

  @doc """
  Generate an order with minimal required fields.
  Requires a product and location to exist.
  """
  def order_fixture(attrs \\ %{}) do
    product = attrs[:product] || product_fixture()
    location = attrs[:location] || location_fixture()

    order_attrs =
      attrs
      |> Map.drop([:product, :location])
      |> Enum.into(%{
        customer_name: "Test Customer",
        customer_phone: "5551234567",
        product_id: product.id,
        prep_location_id: location.id,
        delivery_date: Date.utc_today(),
        delivery_type: "pickup",
        status: "new_order"
      })

    {:ok, order} =
      %Order{}
      |> Order.changeset(order_attrs)
      |> Repo.insert()

    order |> Repo.preload([:product, :prep_location, :customer])
  end

  @doc """
  Generate an order using the full Orders.create_order/1 function.
  This triggers all the business logic (customer lookup, accounting, etc.)
  """
  def order_with_full_creation(attrs \\ %{}) do
    product = attrs[:product] || product_fixture()
    location = attrs[:location] || location_fixture()

    order_attrs =
      attrs
      |> Map.drop([:product, :location])
      |> Enum.into(%{
        "customer_name" => "Test Customer",
        "customer_phone" => "5551234567",
        "product_id" => to_string(product.id),
        "prep_location_id" => to_string(location.id),
        "delivery_date" => Date.to_iso8601(Date.utc_today()),
        "delivery_type" => "pickup",
        "status" => "new_order"
      })

    Orders.create_order(order_attrs)
  end

  @doc """
  Generate an order payment.
  """
  def order_payment_fixture(order, account, attrs \\ %{}) do
    payment_attrs =
      attrs
      |> Enum.into(%{
        "order_id" => to_string(order.id),
        "paid_to_account_id" => to_string(account.id),
        "amount_cents" => 5000,
        "payment_date" => Date.to_iso8601(Date.utc_today()),
        "is_deposit" => false
      })

    {:ok, payment} = Orders.create_order_payment(payment_attrs)
    payment
  end
end

