defmodule LedgrWeb.Storefront.MenuController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.MrMunchMe.Orders

  def index(conn, _params) do
    products = Orders.list_products()

    conn
    |> assign(:storefront, true)
    |> assign(:page_title, "Menu")
    |> render(:index, products: products)
  end

  def show(conn, %{"id" => id}) do
    product = Orders.get_product_with_images!(id)

    conn
    |> assign(:storefront, true)
    |> assign(:page_title, product.name)
    |> render(:show, product: product)
  end
end
