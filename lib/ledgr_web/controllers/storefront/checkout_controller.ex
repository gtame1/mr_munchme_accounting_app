defmodule LedgrWeb.Storefront.CheckoutController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.MrMunchMe.Orders
  alias Ledgr.Domains.MrMunchMe.Inventory
  alias Ledgr.Core.Customers

  @whatsapp_number "525543417149"

  def new(conn, _params) do
    cart = get_session(conn, :cart) || %{}

    if map_size(cart) == 0 do
      conn
      |> put_flash(:error, "Your cart is empty.")
      |> redirect(to: "/mr-munch-me/menu")
    else
      {cart_items, cart_total} = load_cart_items(cart)

      conn
      |> assign(:storefront, true)
      |> assign(:page_title, "Checkout")
      |> render(:new, cart_items: cart_items, cart_total: cart_total, errors: %{})
    end
  end

  def create(conn, %{"checkout" => checkout_params}) do
    cart = get_session(conn, :cart) || %{}

    if map_size(cart) == 0 do
      conn
      |> put_flash(:error, "Your cart is empty.")
      |> redirect(to: "/mr-munch-me/menu")
    else
      {cart_items, cart_total} = load_cart_items(cart)

      # Find or create customer by phone
      customer_phone = String.trim(checkout_params["customer_phone"] || "")
      customer_name = String.trim(checkout_params["customer_name"] || "")
      customer_email = String.trim(checkout_params["customer_email"] || "")

      # Basic validation
      errors =
        %{}
        |> maybe_add_error(customer_name == "", :customer_name, "Name is required")
        |> maybe_add_error(customer_phone == "", :customer_phone, "Phone is required")
        |> maybe_add_error(
          String.trim(checkout_params["delivery_type"] || "") == "",
          :delivery_type,
          "Please select pickup or delivery"
        )
        |> maybe_add_error(
          String.trim(checkout_params["delivery_date"] || "") == "",
          :delivery_date,
          "Please select a date"
        )

      if map_size(errors) > 0 do
        conn
        |> assign(:storefront, true)
        |> assign(:page_title, "Checkout")
        |> put_flash(:error, "Please fix the errors below.")
        |> render(:new, cart_items: cart_items, cart_total: cart_total, errors: errors)
      else
        # Find or create customer
        customer_attrs = %{
          name: customer_name,
          email: if(customer_email != "", do: customer_email, else: nil),
          delivery_address: checkout_params["delivery_address"]
        }

        case Customers.find_or_create_by_phone(customer_phone, customer_attrs) do
          {:ok, customer} ->
            create_orders_for_cart(conn, cart, customer, checkout_params, cart_items, cart_total)

          {:error, _} ->
            conn
            |> assign(:storefront, true)
            |> assign(:page_title, "Checkout")
            |> put_flash(:error, "There was a problem with your customer information.")
            |> render(:new,
              cart_items: cart_items,
              cart_total: cart_total,
              errors: %{customer_phone: "Invalid phone number"}
            )
        end
      end
    end
  end

  defp create_orders_for_cart(conn, cart, customer, checkout_params, cart_items, cart_total) do
    # Get default prep location
    default_location = get_default_prep_location()

    results =
      Enum.map(cart, fn {product_id_str, quantity} ->
        order_attrs = %{
          "customer_id" => customer.id,
          "delivery_type" => checkout_params["delivery_type"],
          "delivery_date" => checkout_params["delivery_date"],
          "delivery_address" => checkout_params["delivery_address"],
          "product_id" => product_id_str,
          "prep_location_id" => to_string(default_location.id),
          "quantity" => to_string(quantity),
          "customer_paid_shipping" => to_string(checkout_params["delivery_type"] == "delivery")
        }

        Orders.create_order(order_attrs)
      end)

    failures = Enum.filter(results, fn
      {:ok, _} -> false
      {:error, _} -> true
    end)

    if Enum.empty?(failures) do
      created_orders = Enum.map(results, fn {:ok, order} -> order end)

      # Build WhatsApp message
      whatsapp_message = build_whatsapp_message(customer, cart_items, cart_total, checkout_params)
      whatsapp_url = "https://wa.me/#{@whatsapp_number}?text=#{URI.encode(whatsapp_message)}"

      conn
      |> delete_session(:cart)
      |> assign(:storefront, true)
      |> assign(:page_title, "Order Confirmed")
      |> render(:confirmation,
        orders: created_orders,
        customer_name: customer.name,
        cart_items: cart_items,
        cart_total: cart_total,
        whatsapp_url: whatsapp_url,
        delivery_type: checkout_params["delivery_type"],
        delivery_date: checkout_params["delivery_date"]
      )
    else
      conn
      |> assign(:storefront, true)
      |> assign(:page_title, "Checkout")
      |> put_flash(:error, "There was a problem placing your order. Please try again.")
      |> render(:new, cart_items: cart_items, cart_total: cart_total, errors: %{})
    end
  end

  defp get_default_prep_location do
    locations = Inventory.list_locations()

    Enum.find(locations, hd(locations), fn loc ->
      loc.code == "CASA_AG"
    end)
  end

  defp build_whatsapp_message(customer, cart_items, cart_total, checkout_params) do
    items_text =
      cart_items
      |> Enum.map(fn item ->
        "- #{item.product.name} x#{item.quantity} ($#{:erlang.float_to_binary(item.subtotal / 100, decimals: 2)})"
      end)
      |> Enum.join("\n")

    total_text = "$#{:erlang.float_to_binary(cart_total / 100, decimals: 2)} MXN"

    delivery_type =
      case checkout_params["delivery_type"] do
        "pickup" -> "Pickup"
        "delivery" -> "Delivery"
        _ -> "N/A"
      end

    """
    Hi! I just placed an order on the MrMunchMe store.

    Name: #{customer.name}
    Phone: #{customer.phone}

    Order:
    #{items_text}

    Total: #{total_text}
    #{delivery_type}: #{checkout_params["delivery_date"]}
    #{if checkout_params["delivery_type"] == "delivery", do: "Address: #{checkout_params["delivery_address"]}", else: ""}
    """
    |> String.trim()
  end

  defp maybe_add_error(errors, true, field, message), do: Map.put(errors, field, message)
  defp maybe_add_error(errors, false, _field, _message), do: errors

  defp load_cart_items(cart) when map_size(cart) == 0, do: {[], 0}

  defp load_cart_items(cart) do
    items =
      Enum.reduce(cart, [], fn {product_id_str, quantity}, acc ->
        case Integer.parse(to_string(product_id_str)) do
          {id, _} ->
            try do
              product = Orders.get_product!(id)
              [%{product: product, quantity: quantity, subtotal: product.price_cents * quantity} | acc]
            rescue
              Ecto.NoResultsError -> acc
            end

          :error ->
            acc
        end
      end)
      |> Enum.sort_by(& &1.product.name)

    total = Enum.reduce(items, 0, fn item, acc -> acc + item.subtotal end)
    {items, total}
  end
end
