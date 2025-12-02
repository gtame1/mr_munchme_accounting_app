defmodule MrMunchMeAccountingAppWeb.ProductController do
  use MrMunchMeAccountingAppWeb, :controller

  alias MrMunchMeAccountingApp.Orders
  alias MrMunchMeAccountingApp.Orders.Product

  def index(conn, _params) do
    products = Orders.list_all_products()
    render(conn, :index, products: products)
  end

  def new(conn, _params) do
    changeset = Orders.change_product(%Product{})
    render(conn, :new, changeset: changeset, action: ~p"/products")
  end

  def create(conn, %{"product" => product_params}) do
    case Orders.create_product(product_params) do
      {:ok, product} ->
        conn
        |> put_flash(:info, "Product created successfully.")
        |> redirect(to: ~p"/products")

      {:error, %Ecto.Changeset{} = changeset} ->
        changeset = Map.put(changeset, :action, :insert)
        render(conn, :new, changeset: changeset, action: ~p"/products")
    end
  end

  def edit(conn, %{"id" => id}) do
    product = Orders.get_product!(id)
    changeset = Orders.change_product(product)
    render(conn, :edit, product: product, changeset: changeset, action: ~p"/products/#{product}")
  end

  def update(conn, %{"id" => id, "product" => product_params}) do
    product = Orders.get_product!(id)

    case Orders.update_product(product, product_params) do
      {:ok, product} ->
        conn
        |> put_flash(:info, "Product updated successfully.")
        |> redirect(to: ~p"/products")

      {:error, %Ecto.Changeset{} = changeset} ->
        changeset = Map.put(changeset, :action, :update)
        render(conn, :edit, product: product, changeset: changeset, action: ~p"/products/#{product}")
    end
  end

  def delete(conn, %{"id" => id}) do
    product = Orders.get_product!(id)
    {:ok, _} = Orders.delete_product(product)

    conn
    |> put_flash(:info, "Product deleted successfully.")
    |> redirect(to: ~p"/products")
  end
end

defmodule MrMunchMeAccountingAppWeb.ProductHTML do
  use MrMunchMeAccountingAppWeb, :html
  import MrMunchMeAccountingAppWeb.CoreComponents
  import Phoenix.Naming

  embed_templates "product_html/*"
end
