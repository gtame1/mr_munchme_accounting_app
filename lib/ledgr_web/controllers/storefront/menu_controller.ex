defmodule LedgrWeb.Storefront.MenuController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.MrMunchMe.Orders

  def index(conn, params) do
    products = Orders.list_products_filtered(params)

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
