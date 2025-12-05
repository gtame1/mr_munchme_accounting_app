defmodule MrMunchMeAccountingAppWeb.RecipeController do
  use MrMunchMeAccountingAppWeb, :controller

  alias MrMunchMeAccountingApp.Inventory.Recepies
  alias MrMunchMeAccountingApp.Inventory.Recipe
  alias MrMunchMeAccountingApp.Orders

  def index(conn, _params) do
    recipes = Recepies.list_recipes()
    recipe_versions_by_product = Recepies.list_all_recipe_versions_by_product()

    # Calculate estimated costs for each recipe
    recipes_with_costs =
      Enum.map(recipes, fn recipe ->
        estimated_cost = Recepies.estimated_recipe_cost(recipe)
        Map.put(recipe, :estimated_cost, estimated_cost)
      end)

    # Calculate estimated costs for all recipe versions
    recipe_versions_by_product_with_costs =
      recipe_versions_by_product
      |> Enum.map(fn {product_id, versions} ->
        versions_with_costs =
          Enum.map(versions, fn version ->
            estimated_cost = Recepies.estimated_recipe_cost(version)
            Map.put(version, :estimated_cost, estimated_cost)
          end)
        {product_id, versions_with_costs}
      end)
      |> Map.new()

    render(conn, :index,
      recipes: recipes_with_costs,
      recipe_versions_by_product: recipe_versions_by_product_with_costs
    )
  end

  def new(conn, _params) do
    # Initialize with at least one empty recipe line
    attrs = %{"recipe_lines" => [%{}]}
    changeset = Recepies.change_recipe(%Recipe{}, attrs)
    form = Phoenix.Component.to_form(changeset)

    ingredient_options = MrMunchMeAccountingApp.Inventory.ingredient_select_options()
    ingredient_options_json = Jason.encode!(Enum.map(ingredient_options, fn {name, code} -> [name, code] end))

    render(conn, :new,
      changeset: changeset,
      form: form,
      action: ~p"/recipes",
      product_options: Orders.product_select_options(),
      ingredient_options: ingredient_options,
      ingredient_options_json: ingredient_options_json
    )
  end

  def create(conn, %{"recipe" => recipe_params}) do
    case Recepies.create_recipe(recipe_params) do
      {:ok, _recipe} ->
        conn
        |> put_flash(:info, "Recipe created successfully.")
        |> redirect(to: ~p"/recipes")

      {:error, %Ecto.Changeset{} = changeset} ->
        changeset = Map.put(changeset, :action, :insert)
        form = Phoenix.Component.to_form(changeset)

        ingredient_options = MrMunchMeAccountingApp.Inventory.ingredient_select_options()
        ingredient_options_json = Jason.encode!(Enum.map(ingredient_options, fn {name, code} -> [name, code] end))

        render(conn, :new,
          changeset: changeset,
          form: form,
          action: ~p"/recipes",
          product_options: Orders.product_select_options(),
          ingredient_options: ingredient_options,
          ingredient_options_json: ingredient_options_json
        )
    end
  end

  def show(conn, %{"id" => id}) do
    recipe = Recepies.get_recipe!(id)
    estimated_cost = Recepies.estimated_recipe_cost(recipe)
    render(conn, :show, recipe: recipe, estimated_cost: estimated_cost)
  end

  def edit(conn, %{"id" => id}) do
    original_recipe = Recepies.get_recipe!(id)

    # Pre-fill with existing recipe data but create a new recipe
    # Default effective_date to today (or day after original if original is today/future)
    new_effective_date =
      if original_recipe.effective_date >= Date.utc_today() do
        Date.add(original_recipe.effective_date, 1)
      else
        Date.utc_today()
      end

    # Build attrs from existing recipe for pre-filling
    attrs = %{
      "product_id" => original_recipe.product_id,
      "effective_date" => new_effective_date,
      "name" => original_recipe.name,
      "description" => original_recipe.description,
      "recipe_lines" =>
        Enum.map(original_recipe.recipe_lines || [], fn line ->
          %{
            "ingredient_code" => line.ingredient_code,
            "quantity" => Decimal.to_string(line.quantity)
          }
        end)
    }

    # Ensure at least one empty recipe line if none exist
    attrs =
      if attrs["recipe_lines"] == [] do
        Map.put(attrs, "recipe_lines", [%{}])
      else
        attrs
      end

    changeset = Recepies.change_recipe(%Recipe{}, attrs)
    form = Phoenix.Component.to_form(changeset)

    ingredient_options = MrMunchMeAccountingApp.Inventory.ingredient_select_options()
    ingredient_options_json = Jason.encode!(Enum.map(ingredient_options, fn {name, code} -> [name, code] end))

    render(conn, :edit,
      original_recipe: original_recipe,
      changeset: changeset,
      form: form,
      action: ~p"/recipes/new_version/#{original_recipe.id}",
      product_options: Orders.product_select_options(),
      ingredient_options: ingredient_options,
      ingredient_options_json: ingredient_options_json
    )
  end

  def create_new_version(conn, %{"id" => original_id, "recipe" => recipe_params}) do
    original_recipe = Recepies.get_recipe!(original_id)

    case Recepies.create_recipe(recipe_params) do
      {:ok, _new_recipe} ->
        conn
        |> put_flash(:info, "New recipe version created successfully. The original recipe remains unchanged for historical accuracy.")
        |> redirect(to: ~p"/recipes")

      {:error, %Ecto.Changeset{} = changeset} ->
        # Debug: Log errors for troubleshooting
        IO.inspect(changeset.errors, label: "Recipe errors")
        if changeset.changes[:recipe_lines] do
          Enum.each(changeset.changes.recipe_lines, fn line_changeset ->
            IO.inspect(line_changeset.errors, label: "Recipe line errors")
          end)
        end

        changeset = Map.put(changeset, :action, :insert)
        form = Phoenix.Component.to_form(changeset)

        ingredient_options = MrMunchMeAccountingApp.Inventory.ingredient_select_options()
        ingredient_options_json = Jason.encode!(Enum.map(ingredient_options, fn {name, code} -> [name, code] end))

        conn
        |> put_flash(:error, "Please fix the errors below and try again.")
        |> render(:edit,
          original_recipe: original_recipe,
          changeset: changeset,
          form: form,
          action: ~p"/recipes/new_version/#{original_recipe.id}",
          product_options: Orders.product_select_options(),
          ingredient_options: ingredient_options,
          ingredient_options_json: ingredient_options_json
        )
    end
  end

  def delete(conn, %{"id" => id}) do
    recipe = Recepies.get_recipe!(id)
    {:ok, _} = Recepies.delete_recipe(recipe)

    conn
    |> put_flash(:info, "Recipe deleted successfully.")
    |> redirect(to: ~p"/recipes")
  end
end

defmodule MrMunchMeAccountingAppWeb.RecipeHTML do
  use MrMunchMeAccountingAppWeb, :html
  import MrMunchMeAccountingAppWeb.CoreComponents
  import Phoenix.Naming

  embed_templates "recipe_html/*"
end
