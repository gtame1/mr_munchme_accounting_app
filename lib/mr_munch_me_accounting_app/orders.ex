defmodule MrMunchMeAccountingApp.Orders do
  import Ecto.Query, warn: false
  alias MrMunchMeAccountingApp.Repo

  alias MrMunchMeAccountingApp.Orders.{Order, Product, OrderPayment}
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
        preload: [product: p, prep_location: l, customer: c]

    base_query
    |> maybe_filter_status(params["status"])
    |> maybe_filter_delivery_type(params["delivery_type"])
    |> maybe_filter_date_range(params["date_from"], params["date_to"])
    |> maybe_filter_product_id(params["product_id"])
    |> maybe_filter_prep_location(params["prep_location_id"])
    |> apply_sort(params["sort_by"], params["sort_dir"])
    |> Repo.all()
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

  def get_order!(id), do: Repo.get!(Order, id) |> Repo.preload([:product, :prep_location, :customer])

  def change_order(%Order{} = order, attrs \\ %{}) do
    Order.changeset(order, attrs)
  end

  def create_order(attrs) do
    Repo.transaction(fn ->
      # If customer_id is provided, populate customer fields from customer record
      # If customer_id is not provided, find or create customer by phone
      attrs =
        cond do
          attrs["customer_id"] || attrs[:customer_id] ->
            # Populate customer fields from the customer record
            customer_id = attrs["customer_id"] || attrs[:customer_id]

            customer = Customers.get_customer!(customer_id)

            # Populate customer fields from customer record
            attrs
            |> Map.put("customer_name", customer.name)
            |> Map.put("customer_phone", customer.phone)
            |> Map.put("customer_email", customer.email || nil)
            |> populate_delivery_address_if_missing(customer)

          true ->
            case handle_customer_creation(attrs) do
              {:ok, customer_id} ->
                Map.put(attrs, "customer_id", customer_id)

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

  # Helper function to find or create customer when customer_id is not provided
  defp handle_customer_creation(attrs) do
    customer_name = attrs["customer_name"] || attrs[:customer_name]
    customer_phone = attrs["customer_phone"] || attrs[:customer_phone]
    customer_email = attrs["customer_email"] || attrs[:customer_email]
    delivery_address = attrs["delivery_address"] || attrs[:delivery_address]

    if customer_name && customer_phone do
      customer_attrs = %{
        name: customer_name,
        phone: customer_phone,
        email: customer_email,
        delivery_address: delivery_address
      }

      case Customers.find_or_create_by_phone(customer_phone, customer_attrs) do
        {:ok, customer} ->
          {:ok, customer.id}

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      {:error, :missing_customer_info}
    end
  end

  def update_order(%Order{} = order, attrs) do
    order
    |> Order.changeset(attrs)
    |> Repo.update()
  end


  def update_order_status(%Order{} = order, new_status) when new_status in @statuses do

    Repo.transaction(fn ->
      {:ok, updated} =
        order
        |> Order.changeset(%{status: new_status})
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
    payments = list_payments_for_order(order.id)

    total_paid_cents =
      Enum.reduce(payments, 0, fn p, acc ->
        (p.amount_cents || 0) + acc
      end)

    {product_total_cents, shipping_cents} = order_total_cents(order)
    order_total_cents = product_total_cents + shipping_cents

    outstanding_cents = max(order_total_cents - total_paid_cents, 0)

    %{
      product_total_cents: product_total_cents,
      shipping_cents: shipping_cents,
      order_total_cents: order_total_cents,
      total_paid_cents: total_paid_cents,
      outstanding_cents: outstanding_cents,
      fully_paid?: outstanding_cents == 0 and order_total_cents > 0,
      partially_paid?: total_paid_cents > 0 and outstanding_cents > 0
    }
  end

  def order_total_cents(%Order{} = order) do
    order = Repo.preload(order, :product)

    base =
      case order.product do
        %{} -> order.product.price_cents || 0
        _ -> 0
      end

    shipping_cents =
      if order.customer_paid_shipping do
        MrMunchMeAccountingApp.Accounting.shipping_fee_cents()
      else
        0
      end

    {base, shipping_cents}
  end


end
