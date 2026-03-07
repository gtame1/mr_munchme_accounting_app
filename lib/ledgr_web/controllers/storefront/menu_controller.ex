defmodule LedgrWeb.Storefront.MenuController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.MrMunchMe.Orders

  def index(conn, params) do
    products = Orders.list_products_with_variants()

    products =
      case params["q"] do
        q when is_binary(q) and q != "" ->
          q_lower = String.downcase(q)

          Enum.filter(products, fn p ->
            String.contains?(String.downcase(p.name), q_lower) ||
              (p.description && String.contains?(String.downcase(p.description), q_lower))
          end)

        _ ->
          products
      end

    conn
    |> assign(:storefront, true)
    |> assign(:page_title, "Menu")
    |> render(:index, products: products, current_q: params["q"] || "")
  end

  def show(conn, %{"id" => id}) do
    product = Orders.get_product_with_images!(id)

    conn
    |> assign(:storefront, true)
    |> assign(:page_title, product.name)
    |> render(:show, product: product)
  end
end
