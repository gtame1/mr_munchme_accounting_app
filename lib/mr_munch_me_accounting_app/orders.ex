defmodule MrMunchMeAccountingApp.Orders do
  import Ecto.Query, warn: false
  alias MrMunchMeAccountingApp.Repo

  alias MrMunchMeAccountingApp.Orders.{Order, Product, OrderPayment, OrderIngredient}
  alias MrMunchMeAccountingApp.Accounting
  alias MrMunchMeAccountingApp.Customers
  alias MrMunchMeAccountingApp.Repo


  # PRODUCTS

  def list_products do
    Repo.all(from p in Product, where: p.active == true, order_by: p.name)
  end

  def list_all_products do
    Repo.all(from p in Product, order_by: p.name)
  end

  def get_product!(id), do: Repo.get!(Product, id)

  def change_product(%Product{} = product, attrs \\ %{}) do
    Product.changeset(product, attrs)
  end

  def create_product(attrs) do
    %Product{}
    |> Product.changeset(attrs)
    |> Repo.insert()
  end

  def update_product(%Product{} = product, attrs) do
    product
    |> Product.changeset(attrs)
    |> Repo.update()
  end

  def delete_product(%Product{} = product) do
    Repo.delete(product)
  end

  def product_select_options do
    list_products()
    |> Enum.map(fn p ->
      label =
        if p.sku do
          "#{p.name} (#{p.sku})"
        else
          p.name
        end

      {label, p.id}
    end)
  end

  # ORDERS

  def list_orders(params \\ %{}) do
    import Ecto.Query

    base_query =
      from o in Order,
        as: :order,
        join: p in assoc(o, :product),
        as: :product,
        join: l in assoc(o, :prep_location),
        as: :prep_location,
        left_join: c in assoc(o, :customer),
        as: :customer,
        preload: [:order_payments, product: p, prep_location: l, customer: c]

    # Exclude canceled orders by default unless explicitly filtering for canceled status
    query =
      if params["status"] == "canceled" do
    base_query
      else
        from o in base_query, where: o.status != "canceled"
      end

    query
    |> maybe_filter_status(params["status"])
    |> maybe_filter_delivery_type(params["delivery_type"])
    |> maybe_filter_date_range(params["date_from"], params["date_to"])
    |> maybe_filter_product_id(params["product_id"])
    |> maybe_filter_prep_location(params["prep_location_id"])
    |> apply_sort(params["sort_by"], params["sort_dir"])
    |> Repo.all()
  end

  def list_canceled_orders(limit \\ 50, offset \\ 0) do
    import Ecto.Query

    canceled_orders =
      from o in Order,
        where: o.status == "canceled",
        join: p in assoc(o, :product),
        join: l in assoc(o, :prep_location),
        left_join: c in assoc(o, :customer),
        preload: [:order_payments, product: p, prep_location: l, customer: c],
        order_by: [desc: o.delivery_date, desc: o.id],
        limit: ^limit,
        offset: ^offset

    canceled_orders
    |> Repo.all()
  end

  def list_delivered_and_paid_orders(limit \\ 10, offset \\ 0) do
    import Ecto.Query

    # Load a larger batch to account for orders that might not be fully paid
    # We'll load 3x the limit to ensure we get enough paid orders
    batch_size = limit * 3

    # Get delivered orders starting from the offset
    delivered_orders =
      from o in Order,
        where: o.status == "delivered",
        join: p in assoc(o, :product),
        join: l in assoc(o, :prep_location),
        left_join: c in assoc(o, :customer),
        preload: [:order_payments, product: p, prep_location: l, customer: c],
        order_by: [desc: o.delivery_date, desc: o.id],
        limit: ^batch_size,
        offset: ^offset

    # Load all orders and filter for fully paid ones, then take only the limit we need
    # order_payments already preloaded — no extra DB calls
    delivered_orders
    |> Repo.all()
    |> Enum.filter(fn order ->
      summary = payment_summary_from_preloaded(order)
      summary.fully_paid?
    end)
    |> Enum.take(limit)
  end

  def count_delivered_and_paid_orders do
    import Ecto.Query

    # Get all delivered orders with payments preloaded (single batch query)
    delivered_orders =
      from o in Order,
        where: o.status == "delivered",
        preload: [:product, :order_payments]

    # Count how many are fully paid — no N+1 since payments are preloaded
    delivered_orders
    |> Repo.all()
    |> Enum.count(fn order ->
      summary = payment_summary_from_preloaded(order)
      summary.fully_paid?
    end)
  end

  @statuses ~w(new_order in_prep ready delivered canceled)
  @delivery_types ~w(pickup delivery)

  defp maybe_filter_status(query, status) when status in @statuses do
    from o in query, where: o.status == ^status
  end

  defp maybe_filter_status(query, _), do: query

  defp maybe_filter_delivery_type(query, type) when type in @delivery_types do
    from o in query, where: o.delivery_type == ^type
  end

  defp maybe_filter_delivery_type(query, _), do: query

  defp maybe_filter_date_range(query, nil, nil), do: query
  defp maybe_filter_date_range(query, date_from, date_to) do
    {:ok, date_from} =
      if is_binary(date_from) and date_from != "" do
        Date.from_iso8601(date_from)
      else
        {:ok, nil}
      end

    {:ok, date_to} =
      if is_binary(date_to) and date_to != "" do
        Date.from_iso8601(date_to)
      else
        {:ok, nil}
      end

    query
    |> maybe_from(date_from)
    |> maybe_to(date_to)
  end

  defp maybe_filter_product_id(query, nil), do: query
  defp maybe_filter_product_id(query, ""), do: query

  defp maybe_filter_product_id(query, product_id) when is_binary(product_id) do
    case Integer.parse(product_id) do
      {id, _} ->
        from o in query, where: o.product_id == ^id

      :error ->
        query
    end
  end

  defp maybe_from(query, nil), do: query
  defp maybe_from(query, date_from) do
    from o in query, where: o.delivery_date >= ^date_from
  end

  defp maybe_to(query, nil), do: query
  defp maybe_to(query, date_to) do
    from o in query, where: o.delivery_date <= ^date_to
  end

  defp maybe_filter_prep_location(query, nil), do: query
  defp maybe_filter_prep_location(query, ""), do: query

  defp maybe_filter_prep_location(query, prep_location_id) when is_binary(prep_location_id) do
    case Integer.parse(prep_location_id) do
      {id, _} ->
        from o in query, where: o.prep_location_id == ^id

      :error ->
        query
    end
  end

  defp maybe_filter_prep_location(query, prep_location_id) when is_integer(prep_location_id) do
    from o in query, where: o.prep_location_id == ^prep_location_id
  end

  defp apply_sort(query, sort_by, sort_dir) do
    import Ecto.Query

    dir =
      case sort_dir do
        "asc" -> :asc
        _ -> :desc
      end

    case sort_by do
      "customer_name" ->
        from [order: o] in query, order_by: [{^dir, o.customer_name}]

      "delivery_date" ->
        from [order: o] in query, order_by: [{^dir, o.delivery_date}]

      "status" ->
        from [order: o] in query, order_by: [{^dir, o.status}]

      "product" ->
        from [product: p] in query, order_by: [{^dir, p.name}]

      "price_cents" ->
        from [product: p] in query, order_by: [{^dir, p.price_cents}]

      _ ->
        from [order: o] in query, order_by: [{^dir, o.delivery_date}]
    end
  end

  @doc """
  Gets orders for a specific month, grouped by delivery date.
  Returns a map where keys are dates (Date) and values are lists of orders.
  Excludes canceled orders by default.
  """
  def list_orders_for_calendar_month(year, month, opts \\ []) do
    import Ecto.Query

    exclude_canceled = Keyword.get(opts, :exclude_canceled, true)

    # Calculate first and last day of the month
    first_day = Date.new!(year, month, 1)
    last_day = Date.end_of_month(first_day)

    base_query =
      from o in Order,
        where: o.delivery_date >= ^first_day and o.delivery_date <= ^last_day,
        join: p in assoc(o, :product),
        join: l in assoc(o, :prep_location),
        left_join: c in assoc(o, :customer),
        preload: [product: p, prep_location: l, customer: c],
        order_by: [asc: o.delivery_date, asc: o.id]

    query =
      if exclude_canceled do
        from o in base_query, where: o.status != "canceled"
      else
        base_query
      end

    orders = Repo.all(query)

    # Group orders by delivery date
    Enum.group_by(orders, & &1.delivery_date, & &1)
  end

  def get_order!(id), do: Repo.get!(Order, id) |> Repo.preload([:product, :prep_location, :customer, :order_ingredients])

  def change_order(%Order{} = order, attrs \\ %{}) do
    Order.changeset(order, attrs)
  end

  def create_order(attrs) do
    Repo.transaction(fn ->
      # If customer_id is provided, populate customer fields from customer record
      # If customer_id is not provided, find or create customer by phone
      customer_id = attrs["customer_id"] || attrs[:customer_id]
      customer_id = if customer_id in [nil, ""], do: nil, else: customer_id

      attrs =
        cond do
          customer_id ->
            # Populate customer fields from the customer record
            customer = Customers.get_customer!(customer_id)
            populate_customer_fields(attrs, customer)

          true ->
            case handle_customer_creation(attrs) do
              {:ok, customer} ->
                attrs
                |> Map.put("customer_id", customer.id)
                |> populate_customer_fields(customer)

              {:error, changeset} ->
                Repo.rollback(changeset)
            end
        end

      case %Order{}
           |> Order.changeset(attrs)
           |> Repo.insert() do
        {:ok, order} ->
          # Try to create the accounting entry; if it fails, we don't crash the order creation.
          _ = Accounting.record_order_created(order)
          order

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  # Populates denormalized customer fields on order attrs from the customer record.
  # This ensures the order always reflects the canonical customer data.
  defp populate_customer_fields(attrs, customer) do
    attrs
    |> Map.put("customer_name", customer.name)
    |> Map.put("customer_phone", customer.phone)
    |> Map.put("customer_email", customer.email || nil)
    |> populate_delivery_address_if_missing(customer)
  end

  # Helper to populate delivery_address from customer if not already provided in order
  defp populate_delivery_address_if_missing(attrs, customer) do
    delivery_address = attrs["delivery_address"] || attrs[:delivery_address]

    if (!delivery_address || String.trim(delivery_address || "") == "") &&
         customer.delivery_address &&
         String.trim(customer.delivery_address) != "" do
      Map.put(attrs, "delivery_address", customer.delivery_address)
    else
      attrs
    end
  end

  # Helper function to create a new customer when customer_id is not provided.
  # If the phone number already belongs to an existing customer, returns an error
  # prompting the user to select them from the existing customer list.
  defp handle_customer_creation(attrs) do
    customer_name = attrs["customer_name"] || attrs[:customer_name]
    customer_phone = attrs["customer_phone"] || attrs[:customer_phone]
    customer_email = attrs["customer_email"] || attrs[:customer_email]
    delivery_address = attrs["delivery_address"] || attrs[:delivery_address]

    if customer_name && customer_phone do
      # Check if a customer with this phone already exists
      case Customers.get_customer_by_phone(customer_phone) do
        %Customers.Customer{} = existing ->
          # Block creation — tell user to pick from existing list
          changeset =
            %Order{}
            |> Order.changeset(attrs)
            |> Ecto.Changeset.add_error(
              :customer_phone,
              "already belongs to #{existing.name}. Please select them from the existing customer list."
            )

          {:error, changeset}

        nil ->
          customer_attrs = %{
            name: customer_name,
            phone: customer_phone,
            email: customer_email,
            delivery_address: delivery_address
          }

          Customers.create_customer(customer_attrs)
      end
    else
      {:error, :missing_customer_info}
    end
  end

  def update_order(%Order{} = order, attrs) do
    customer_id = attrs["customer_id"] || attrs[:customer_id]
    customer_id = if customer_id in [nil, ""], do: nil, else: customer_id

    customer_name = attrs["customer_name"] || attrs[:customer_name]
    customer_phone = attrs["customer_phone"] || attrs[:customer_phone]

    cond do
      customer_id ->
        # Existing customer selected — sync denormalized fields from customer record
        customer = Customers.get_customer!(customer_id)
        attrs = populate_customer_fields(attrs, customer)
        order |> Order.changeset(attrs) |> Repo.update()

      customer_name && customer_phone ->
        # New customer from edit form — check for duplicate phone, create if new
        case handle_customer_creation(attrs) do
          {:ok, customer} ->
            attrs =
              attrs
              |> Map.put("customer_id", customer.id)
              |> populate_customer_fields(customer)

            order |> Order.changeset(attrs) |> Repo.update()

          {:error, changeset} ->
            {:error, changeset}
        end

      true ->
        # No customer change — just update other fields
        order |> Order.changeset(attrs) |> Repo.update()
    end
  end


  def update_order_status(%Order{} = order, new_status) when new_status in @statuses do
    # Auto-set actual_delivery_date when marking as delivered
    attrs =
      if new_status == "delivered" do
        %{status: new_status, actual_delivery_date: order.actual_delivery_date || Date.utc_today()}
      else
        %{status: new_status}
      end

    Repo.transaction(fn ->
      {:ok, updated} =
        order
        |> Order.changeset(attrs)
        |> Repo.update()

      Accounting.handle_order_status_change(updated, new_status)

      updated
    end)
  end

  def update_order_status(%Order{} = _order, _bad_status) do
    {:error, :invalid_status}
  end


    # ---------------------------
  # PAYMENTS
  # ---------------------------

  def list_payments_for_order(order_id) do
    Repo.all(
      from p in OrderPayment,
        where: p.order_id == ^order_id,
        order_by: [asc: p.payment_date, asc: p.id],
        preload: [:paid_to_account]
    )
  end

  def list_all_payments do
    Repo.all(
      from p in OrderPayment,
        order_by: [desc: p.payment_date, desc: p.id],
        preload: [:order, :paid_to_account, :partner]
    )
  end

  def get_order_payment!(id) do
    Repo.get!(OrderPayment, id)
    |> Repo.preload([:order, :paid_to_account, :partner, :partner_payable_account])
  end

  def change_order_payment(%OrderPayment{} = payment, attrs \\ %{}) do
    OrderPayment.changeset(payment, attrs)
  end

  def create_order_payment(attrs) do
    Repo.transaction(fn ->
      with {:ok, payment} <-
             %OrderPayment{}
             |> OrderPayment.changeset(attrs)
             |> Repo.insert(),
           {:ok, _entry} <- Accounting.record_order_payment(payment) do
        payment
      else
        {:error, %Ecto.Changeset{} = changeset} ->
          Repo.rollback(changeset)

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  def update_order_payment(%OrderPayment{} = payment, attrs) do
    Repo.transaction(fn ->
      with {:ok, payment} <-
             payment
             |> OrderPayment.changeset(attrs)
             |> Repo.update(),
           payment <- payment |> Repo.preload([:order, :paid_to_account, :partner, :partner_payable_account]),
           {:ok, _entry} <- Accounting.update_order_payment_journal_entry(payment) do
        payment
      else
        {:error, %Ecto.Changeset{} = changeset} ->
          Repo.rollback(changeset)

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  def delete_order_payment(%OrderPayment{} = payment) do
    Repo.transaction(fn ->
      # Find and delete the related journal entry
      reference = "Order ##{payment.order_id} payment ##{payment.id}"

      journal_entry =
        from(je in MrMunchMeAccountingApp.Accounting.JournalEntry, where: je.reference == ^reference)
        |> Repo.one()

      if journal_entry do
        Repo.delete!(journal_entry)
      end

      # Delete the payment
      Repo.delete!(payment)
    end)
    |> case do
      {:ok, payment} -> {:ok, payment}
      {:error, reason} -> {:error, reason}
    end
  end

    # ---------------------------
  # PAYMENT SUMMARY PER ORDER
  # ---------------------------

  def payment_summary(%Order{} = order) do
    order = Repo.preload(order, [:product, :order_payments])
    compute_payment_summary(order, order.order_payments)
  end

  @doc """
  Compute payment summary from an order that already has :product and :order_payments preloaded.
  No additional DB queries — use this in batch/list contexts to avoid N+1.
  """
  def payment_summary_from_preloaded(%Order{} = order) do
    payments = order.order_payments || []
    compute_payment_summary(order, payments)
  end

  defp compute_payment_summary(%Order{} = order, payments) when is_list(payments) do
    total_paid_cents =
      Enum.reduce(payments, 0, fn p, acc ->
        (p.amount_cents || 0) + acc
      end)

    # Get the original price before discount for display
    original_price_cents =
      case order.product do
        %{} -> order.product.price_cents || 0
        _ -> 0
      end

    discount_cents = calculate_discount_cents(order, original_price_cents)

    {product_total_cents, shipping_cents} = order_total_cents(order)
    order_total_cents = product_total_cents + shipping_cents

    outstanding_cents = max(order_total_cents - total_paid_cents, 0)

    if order.is_gift do
      %{
        product_total_cents: product_total_cents,
        original_price_cents: original_price_cents,
        discount_cents: discount_cents,
        shipping_cents: shipping_cents,
        order_total_cents: 0,
        total_paid_cents: 0,
        outstanding_cents: 0,
        fully_paid?: true,
        partially_paid?: false
      }
    else
      %{
        product_total_cents: product_total_cents,
        original_price_cents: original_price_cents,
        discount_cents: discount_cents,
        shipping_cents: shipping_cents,
        order_total_cents: order_total_cents,
        total_paid_cents: total_paid_cents,
        outstanding_cents: outstanding_cents,
        fully_paid?: outstanding_cents == 0 and order_total_cents > 0,
        partially_paid?: total_paid_cents > 0 and outstanding_cents > 0
      }
    end
  end

  def order_total_cents(%Order{} = order) do
    order = Repo.preload(order, :product)

    base =
      case order.product do
        %{} -> order.product.price_cents || 0
        _ -> 0
      end

    # Apply discount to the base product price
    discount_cents = calculate_discount_cents(order, base)
    discounted_base = max(base - discount_cents, 0)

    shipping_cents =
      if order.customer_paid_shipping do
        MrMunchMeAccountingApp.Accounting.shipping_fee_cents()
      else
        0
      end

    {discounted_base, shipping_cents}
  end

  defp calculate_discount_cents(%Order{discount_type: "flat", discount_value: value}, _base)
       when not is_nil(value) do
    # discount_value is in pesos, convert to cents
    value
    |> Decimal.mult(Decimal.new(100))
    |> Decimal.round(0)
    |> Decimal.to_integer()
  end

  defp calculate_discount_cents(%Order{discount_type: "percentage", discount_value: value}, base)
       when not is_nil(value) do
    # Calculate percentage of base price
    base
    |> Decimal.new()
    |> Decimal.mult(value)
    |> Decimal.div(Decimal.new(100))
    |> Decimal.round(0)
    |> Decimal.to_integer()
  end

  defp calculate_discount_cents(_order, _base), do: 0

  # ORDER INGREDIENTS

  def update_order_ingredients(%Order{} = order, ingredients_attrs) when is_list(ingredients_attrs) do
    Repo.transaction(fn ->
      # Delete existing order ingredients
      Repo.delete_all(from oi in OrderIngredient, where: oi.order_id == ^order.id)

      # Insert new order ingredients
      Enum.each(ingredients_attrs, fn attrs ->
        %OrderIngredient{}
        |> OrderIngredient.changeset(Map.put(attrs, "order_id", order.id))
        |> Repo.insert!()
      end)

      # Reload order with ingredients
      Repo.get!(Order, order.id) |> Repo.preload([:product, :prep_location, :customer, :order_ingredients])
    end)
  end

  def update_order_ingredients(%Order{} = _order, _), do: {:error, :invalid_attrs}

end
