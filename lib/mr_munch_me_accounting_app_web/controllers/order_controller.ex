defmodule MrMunchMeAccountingAppWeb.OrderController do
  use MrMunchMeAccountingAppWeb, :controller

  alias MrMunchMeAccountingApp.Orders
  alias MrMunchMeAccountingApp.Orders.{Order, OrderPayment}
  alias MrMunchMeAccountingApp.{Inventory, Accounting, Repo, Customers, Partners}

  def index(conn, params) do
    # 1) Apply defaults directly to params
    params =
      params
      |> Map.put_new("sort_by", "delivery_date")
      |> Map.put_new("sort_dir", "asc")

    # 2) Use these params for the query
    all_orders = Orders.list_orders(params)

    # Calculate payment summaries for each order
    orders_with_payment_status =
      Enum.map(all_orders, fn order ->
        payment_summary = Orders.payment_summary(order)
        Map.put(order, :payment_summary, payment_summary)
      end)

    # 3) Separate active orders from completed (delivered & paid) orders
    {active_orders, _completed_orders} =
      Enum.split_with(orders_with_payment_status, fn order ->
        !(order.status == "delivered" && order.payment_summary.fully_paid?)
      end)

    # 4) Get completed orders with pagination
    # We show all completed orders up to the current offset + limit
    completed_limit = 10
    completed_offset =
      case params["completed_offset"] do
        nil -> 0
        "" -> 0
        val -> String.to_integer(val)
      end

    # Load all completed orders from 0 to offset+limit
    total_to_load = completed_offset + completed_limit
    completed_orders = Orders.list_delivered_and_paid_orders(total_to_load, 0)

    # Calculate payment summaries for completed orders
    completed_orders_with_payment_status =
      Enum.map(completed_orders, fn order ->
        payment_summary = Orders.payment_summary(order)
        Map.put(order, :payment_summary, payment_summary)
      end)

    # Check if there are more completed orders by trying to load one more
    # If we got exactly what we asked for, there might be more
    has_more_completed = length(completed_orders_with_payment_status) >= total_to_load

    # 5) Build filters map from the same params (so UI & query are in sync)
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
      orders: active_orders,
      completed_orders: completed_orders_with_payment_status,
      completed_offset: completed_offset,
      has_more_completed: has_more_completed,
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
      location_options: Inventory.list_locations() |> Enum.map(&{&1.name, &1.id}),
      customer_options: Customers.customer_select_options()
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
      location_options: Inventory.list_locations() |> Enum.map(&{&1.name, &1.id}),
      customer_options: Customers.customer_select_options()
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
          location_options: Inventory.list_locations() |> Enum.map(&{&1.name, &1.id}),
          customer_options: Customers.customer_select_options()
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
      paid_to_account_options: Accounting.cash_or_payable_account_options(),
      partner_options: Partners.partner_select_options(),
      liability_account_options: Accounting.liability_account_options()
    )
  end

  def create_payment(conn, %{"id" => id, "order_payment" => params}) do
    order = Orders.get_order!(id)

    # Parse payment_date string to Date for comparison
    payment_date = Date.from_iso8601!(params["payment_date"])

    # Parse amount as decimal and convert to cents
    amount_cents =
      case Decimal.parse(params["amount"] || "0") do
        {dec, ""} ->
          dec
          |> Decimal.mult(Decimal.new(100))
          |> Decimal.round(0)
          |> Decimal.to_integer()

        _ ->
          nil
      end

    # Parse split payment amounts and convert to cents
    customer_amount_cents =
      if params["customer_amount"] do
        case Decimal.parse(params["customer_amount"]) do
          {dec, ""} ->
            dec
            |> Decimal.mult(Decimal.new(100))
            |> Decimal.round(0)
            |> Decimal.to_integer()

          _ ->
            nil
        end
      else
        nil
      end

    partner_amount_cents =
      if params["partner_amount"] do
        case Decimal.parse(params["partner_amount"]) do
          {dec, ""} ->
            dec
            |> Decimal.mult(Decimal.new(100))
            |> Decimal.round(0)
            |> Decimal.to_integer()

          _ ->
            nil
        end
      else
        nil
      end

    # Make sure we tie the payment to the correct order_id explicitly
    attrs =
      params
      |> Map.put("order_id", order.id)
      |> Map.put("is_deposit", payment_date < order.delivery_date)
      |> Map.put("amount_cents", amount_cents)
      |> Map.put("customer_amount_cents", customer_amount_cents)
      |> Map.put("partner_amount_cents", partner_amount_cents)
      |> Map.drop(["customer_amount", "partner_amount", "amount"])

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
          paid_to_account_options: Accounting.cash_or_payable_account_options(),
          partner_options: Partners.partner_select_options(),
          liability_account_options: Accounting.liability_account_options()
        )
    end
  end

  def calendar(conn, params) do
    # Parse year and month from params, default to current month
    today = Date.utc_today()
    year = case params["year"] do
      nil -> today.year
      year_str -> String.to_integer(year_str)
    end

    month = case params["month"] do
      nil -> today.month
      month_str -> String.to_integer(month_str)
    end

    # Ensure valid month range
    month = cond do
      month < 1 -> 1
      month > 12 -> 12
      true -> month
    end

    # Get orders grouped by delivery date for this month
    orders_by_date = Orders.list_orders_for_calendar_month(year, month)

    # Calculate first day of month and last day
    first_day = Date.new!(year, month, 1)
    last_day = Date.end_of_month(first_day)

    # Calculate first day of calendar grid (might be from previous month)
    # Date.day_of_week returns 1=Monday, 7=Sunday, but we want Sunday=0
    weekday = Date.day_of_week(first_day)
    # Convert: 7 (Sunday) -> 0, 1 (Monday) -> 1, etc.
    days_from_sunday = if weekday == 7, do: 0, else: weekday
    calendar_start = Date.add(first_day, -days_from_sunday)

    # Calculate last day of calendar grid (complete 6 weeks = 42 days)
    calendar_end = Date.add(calendar_start, 41)

    render(conn, :calendar,
      year: year,
      month: month,
      first_day: first_day,
      last_day: last_day,
      calendar_start: calendar_start,
      calendar_end: calendar_end,
      orders_by_date: orders_by_date,
      today: today
    )
  end
end


defmodule MrMunchMeAccountingAppWeb.OrderHTML do
  use MrMunchMeAccountingAppWeb, :html
  import MrMunchMeAccountingAppWeb.CoreComponents

  embed_templates "order_html/*"

  def prev_month(year, month) do
    if month == 1 do
      %{year: year - 1, month: 12}
    else
      %{year: year, month: month - 1}
    end
  end

  def next_month(year, month) do
    if month == 12 do
      %{year: year + 1, month: 1}
    else
      %{year: year, month: month + 1}
    end
  end
end
