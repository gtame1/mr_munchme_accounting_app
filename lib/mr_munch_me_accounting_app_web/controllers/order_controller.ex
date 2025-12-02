defmodule MrMunchMeAccountingAppWeb.OrderController do
  use MrMunchMeAccountingAppWeb, :controller

  alias MrMunchMeAccountingApp.Orders
  alias MrMunchMeAccountingApp.Orders.{Order, OrderPayment}
  alias MrMunchMeAccountingApp.{Inventory, Accounting, Repo}

  def index(conn, params) do
    # 1) Apply defaults directly to params
    params =
      params
      |> Map.put_new("sort_by", "delivery_date")
      |> Map.put_new("sort_dir", "asc")

    # 2) Use these params for the query
    orders = Orders.list_orders(params)

    # 3) Build filters map from the same params (so UI & query are in sync)
    filters = %{
      status: params["status"] || "",
      delivery_type: params["delivery_type"] || "",
      product_id: params["product_id"] || "",
      prep_location_id: params["prep_location_id"] || "",
      date_from: params["date_from"] || "",
      date_to: params["date_to"] || "",
      sort_by: params["sort_by"],
      sort_dir: params["sort_dir"]
    }

    render(conn, :index,
      orders: orders,
      filters: filters,
      product_filter_options: Orders.product_select_options(),
      location_filter_options: Inventory.list_locations() |> Enum.map(&{&1.name, &1.id})
    )
  end

  def new(conn, _params) do
    changeset = Orders.change_order(%Order{})

    render(conn, :new,
      changeset: changeset,
      action: ~p"/orders",
      product_options: Orders.product_select_options(),
      location_options: Inventory.list_locations() |> Enum.map(&{&1.name, &1.id})
    )
  end

  def create(conn, %{"order" => params}) do
    case Orders.create_order(params) do
      {:ok, order} ->
        conn
        |> put_flash(:info, "Order created.")
        |> redirect(to: ~p"/orders/#{order.id}")

      {:error, %Ecto.Changeset{} = changeset} ->
        changeset = Map.put(changeset, :action, :insert)

        render(conn, :new,
          changeset: changeset,
          action: ~p"/orders",
          product_options: Orders.product_select_options(),
          location_options: Inventory.list_locations() |> Enum.map(&{&1.name, &1.id})
        )
    end
  end

  def show(conn, %{"id" => id}) do
    order = Orders.get_order!(id)
    payments = Orders.list_payments_for_order(order.id)
    payment_summary = Orders.payment_summary(order)

    render(conn, :show,
      order: order,
      payments: payments,
      payment_summary: payment_summary
    )
  end

  def edit(conn, %{"id" => id}) do
    order = Orders.get_order!(id)
    changeset = Orders.change_order(order)

    render(conn, :edit,
      order: order,
      changeset: changeset,
      product_options: Orders.product_select_options(),
      location_options: Inventory.list_locations() |> Enum.map(&{&1.name, &1.id})
    )
  end

  def update(conn, %{"id" => id, "order" => order_params}) do
    order = Orders.get_order!(id) |> Repo.preload([:product, :prep_location])

    case Orders.update_order(order, order_params) do
      {:ok, order} ->
        conn
        |> put_flash(:info, "Order updated successfully.")
        |> redirect(to: ~p"/orders/#{order.id}")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :edit,
          order: order,
          changeset: changeset,
          product_options: Orders.product_select_options(),
          location_options: Inventory.list_locations() |> Enum.map(&{&1.name, &1.id})
        )
    end
  end

  def update_status(conn, %{"id" => id, "status" => %{"status" => new_status}}) do
    order = Orders.get_order!(id)

    case Orders.update_order_status(order, new_status) do
      {:ok, _updated} ->
        conn
        |> put_flash(:info, "Order status updated to #{new_status}.")
        |> redirect(to: ~p"/orders")

      {:error, :invalid_status} ->
        conn
        |> put_flash(:error, "Invalid status change.")
        |> redirect(to: ~p"/orders/#{order.id}")

      {:error, %Ecto.Changeset{} = _changeset} ->
        # This would be rare, but handle it nicely
        conn
        |> put_flash(:error, "Could not update status.")
        |> redirect(to: ~p"/orders/#{order.id}")
    end
  end

  def new_payment(conn, %{"id" => id}) do
    order = Orders.get_order!(id)

    changeset =
      Orders.change_order_payment(%OrderPayment{
        order_id: order.id,
        payment_date: Date.utc_today()
      })

    render(conn, :new_payment,
      order: order,
      changeset: changeset,
      action: ~p"/orders/#{order.id}/payments",
      paid_to_account_options: Accounting.cash_or_payable_account_options()
    )
  end

  def create_payment(conn, %{"id" => id, "order_payment" => params}) do
    order = Orders.get_order!(id)

    # Parse payment_date string to Date for comparison
    payment_date = Date.from_iso8601!(params["payment_date"])

    # Parse amount as decimal and convert to cents
    amount_cents =
      case Decimal.parse(params["amount"]) do
        {dec, ""} ->
          dec
          |> Decimal.mult(Decimal.new(100))
          |> Decimal.round(0)
          |> Decimal.to_integer()

        _ ->
          nil
      end


    # Make sure we tie the payment to the correct order_id explicitly
    attrs =
      params
      |> Map.put("order_id", order.id)
      |> Map.put("is_deposit", payment_date < order.delivery_date)
      |> Map.put("amount_cents", amount_cents)

    case Orders.create_order_payment(attrs) do
      {:ok, _payment} ->
        conn
        |> put_flash(:info, "Payment recorded successfully.")
        |> redirect(to: ~p"/orders/#{order.id}")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new_payment,
          order: order,
          changeset: changeset,
          action: ~p"/orders/#{order.id}/payments",
          paid_to_account_options: Accounting.cash_or_payable_account_options()
        )
    end
  end
end


defmodule MrMunchMeAccountingAppWeb.OrderHTML do
  use MrMunchMeAccountingAppWeb, :html
  import MrMunchMeAccountingAppWeb.CoreComponents

  embed_templates "order_html/*"
end
