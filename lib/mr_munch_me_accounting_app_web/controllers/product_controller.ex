defmodule MrMunchMeAccountingAppWeb.ProductController do
  use MrMunchMeAccountingAppWeb, :controller

  alias MrMunchMeAccountingApp.Orders
  alias MrMunchMeAccountingApp.Orders.Product
  alias MrMunchMeAccountingApp.Inventory.Recepies

  def index(conn, _params) do
    products = Orders.list_all_products()
    render(conn, :index, products: products)
  end

  def new(conn, _params) do
    changeset = Orders.change_product(%Product{})
    recipe_options = Recepies.products_with_recipes_select_options()
    render(conn, :new,
      changeset: changeset,
      action: ~p"/products",
      recipe_options: recipe_options
    )
  end

  def create(conn, %{"product" => product_params}) do
    # Extract recipe-related params
    copy_recipe_from_product_id = product_params["copy_recipe_from_product_id"]
    create_recipe = product_params["create_recipe"] == "true"

    # Filter out recipe-related params before creating product
    product_attrs =
      product_params
      |> Map.delete("create_recipe")
      |> Map.delete("copy_recipe_from_product_id")

    case Orders.create_product(product_attrs) do
      {:ok, product} ->
        # If recipe copying was requested and a source product was selected, copy the recipe
        if create_recipe && copy_recipe_from_product_id && copy_recipe_from_product_id != "" do
          source_product = Orders.get_product!(copy_recipe_from_product_id)

          case Recepies.copy_recipe_from_product(source_product, product) do
            {:ok, _recipe} ->
              conn
              |> put_flash(:info, "Product and recipe created successfully.")
              |> redirect(to: ~p"/products")

            {:error, :no_recipe_found} ->
              conn
              |> put_flash(:warning, "Product created, but the source product doesn't have a recipe to copy.")
              |> redirect(to: ~p"/products")

            {:error, _changeset} ->
              conn
              |> put_flash(:warning, "Product created, but there was an error copying the recipe. You can create a recipe manually.")
              |> redirect(to: ~p"/products")
          end
        else
          conn
          |> put_flash(:info, "Product created successfully.")
          |> redirect(to: ~p"/products")
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        changeset = Map.put(changeset, :action, :insert)
        recipe_options = Recepies.products_with_recipes_select_options()
        render(conn, :new,
          changeset: changeset,
          action: ~p"/products",
          recipe_options: recipe_options
        )
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
      {:ok, _product} ->
        conn
        |> put_flash(:info, "Product updated successfully.")
        |> redirect(to: ~p"/products")

      {:error, %Ecto.Changeset{} = changeset} ->
        changeset = Map.put(changeset, :action, :update)
        render(conn, :edit, product: product, changeset: changeset, action: ~p"/products/#{product}")
    end
  end

  def delete(conn, %{"id" => id}) do
    {:ok, _} =
      Orders.get_product!(id)
      |> Orders.delete_product()

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
