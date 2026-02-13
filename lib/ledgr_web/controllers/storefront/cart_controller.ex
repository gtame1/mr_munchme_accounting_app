defmodule LedgrWeb.Storefront.CartController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.MrMunchMe.Orders

  def index(conn, _params) do
    cart = get_session(conn, :cart) || %{}
    {cart_items, cart_total} = load_cart_items(cart)

    conn
    |> assign(:storefront, true)
    |> assign(:page_title, "Your Cart")
    |> render(:index, cart_items: cart_items, cart_total: cart_total)
  end

  def add(conn, %{"product_id" => product_id, "quantity" => quantity}) do
    product_id_str = to_string(product_id)
    quantity = max(String.to_integer(to_string(quantity)), 1)

    # Verify product exists and is active
    product = Orders.get_product!(product_id)
    unless product.active, do: raise("Product not active")

    cart = get_session(conn, :cart) || %{}
    existing_qty = Map.get(cart, product_id_str, 0)
    cart = Map.put(cart, product_id_str, existing_qty + quantity)

    conn
    |> put_session(:cart, cart)
    |> put_flash(:info, "#{product.name} added to cart!")
    |> redirect(to: "/mr-munch-me/menu")
  end

  def update(conn, %{"product_id" => product_id, "quantity" => quantity}) do
    product_id_str = to_string(product_id)
    quantity = String.to_integer(to_string(quantity))
    cart = get_session(conn, :cart) || %{}

    cart =
      if quantity <= 0 do
        Map.delete(cart, product_id_str)
      else
        Map.put(cart, product_id_str, quantity)
      end

    conn
    |> put_session(:cart, cart)
    |> redirect(to: "/mr-munch-me/cart")
  end

  def remove(conn, %{"product_id" => product_id}) do
    product_id_str = to_string(product_id)
    cart = get_session(conn, :cart) || %{}
    cart = Map.delete(cart, product_id_str)

    conn
    |> put_session(:cart, cart)
    |> put_flash(:info, "Item removed from cart.")
    |> redirect(to: "/mr-munch-me/cart")
  end

  defp load_cart_items(cart) when map_size(cart) == 0, do: {[], 0}

  defp load_cart_items(cart) do
    items =
      Enum.reduce(cart, [], fn {product_id_str, quantity}, acc ->
        case Integer.parse(product_id_str) do
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
