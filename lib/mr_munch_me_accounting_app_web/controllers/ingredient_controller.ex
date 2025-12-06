defmodule MrMunchMeAccountingAppWeb.IngredientController do
  use MrMunchMeAccountingAppWeb, :controller

  alias MrMunchMeAccountingApp.Inventory
  alias MrMunchMeAccountingApp.Inventory.Ingredient

  def index(conn, _params) do
    ingredients = Inventory.list_ingredients()
    render(conn, :index, ingredients: ingredients)
  end

  def new(conn, _params) do
    changeset = Inventory.change_ingredient(%Ingredient{})
    inventory_type_options = [
      {"Ingredients", "ingredients"},
      {"Packing", "packing"},
      {"Kitchen Equipment", "kitchen"},
      {"Other", "other"}
    ]
    render(conn, :new,
      changeset: changeset,
      action: ~p"/ingredients",
      inventory_type_options: inventory_type_options
    )
  end

  def create(conn, %{"ingredient" => ingredient_params}) do
    case Inventory.create_ingredient(ingredient_params) do
      {:ok, _ingredient} ->
        conn
        |> put_flash(:info, "Ingredient created successfully.")
        |> redirect(to: ~p"/ingredients")

      {:error, %Ecto.Changeset{} = changeset} ->
        changeset = Map.put(changeset, :action, :insert)
        inventory_type_options = [
          {"Ingredients", "ingredients"},
          {"Packing", "packing"},
          {"Kitchen Equipment", "kitchen"}
        ]
        render(conn, :new,
          changeset: changeset,
          action: ~p"/ingredients",
          inventory_type_options: inventory_type_options
        )
    end
  end

  def edit(conn, %{"id" => id}) do
    ingredient = Inventory.get_ingredient!(id)
    changeset = Inventory.change_ingredient(ingredient)
    inventory_type_options = [
      {"Ingredients", "ingredients"},
      {"Packing", "packing"},
      {"Kitchen Equipment", "kitchen"},
      {"Other", "other"}
    ]
    render(conn, :edit,
      ingredient: ingredient,
      changeset: changeset,
      action: ~p"/ingredients/#{ingredient}",
      inventory_type_options: inventory_type_options
    )
  end

  def update(conn, %{"id" => id, "ingredient" => ingredient_params}) do
    ingredient = Inventory.get_ingredient!(id)

    case Inventory.update_ingredient(ingredient, ingredient_params) do
      {:ok, _ingredient} ->
        conn
        |> put_flash(:info, "Ingredient updated successfully.")
        |> redirect(to: ~p"/ingredients")

      {:error, %Ecto.Changeset{} = changeset} ->
        changeset = Map.put(changeset, :action, :update)
        inventory_type_options = [
          {"Ingredients", "ingredients"},
          {"Packing", "packing"},
          {"Kitchen Equipment", "kitchen"}
        ]
        render(conn, :edit,
          ingredient: ingredient,
          changeset: changeset,
          action: ~p"/ingredients/#{ingredient}",
          inventory_type_options: inventory_type_options
        )
    end
  end

  def delete(conn, %{"id" => id}) do
    ingredient = Inventory.get_ingredient!(id)
    {:ok, _} = Inventory.delete_ingredient(ingredient)

    conn
    |> put_flash(:info, "Ingredient deleted successfully.")
    |> redirect(to: ~p"/ingredients")
  end
end

defmodule MrMunchMeAccountingAppWeb.IngredientHTML do
  use MrMunchMeAccountingAppWeb, :html
  import MrMunchMeAccountingAppWeb.CoreComponents
  import Phoenix.Naming

  embed_templates "ingredient_html/*"
end
