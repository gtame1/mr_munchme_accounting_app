defmodule MrMunchMeAccountingApp.Inventory.Recepies do
  @moduledoc """
  Recepies context: recipes for products.
  """
  import Ecto.Query
  alias MrMunchMeAccountingApp.Repo
  alias MrMunchMeAccountingApp.Orders.Product
  alias MrMunchMeAccountingApp.Inventory.{Recipe}
  alias MrMunchMeAccountingApp.Inventory

  @packaging_codes ~w(
    PACKING_PLASTICO
    BOLSA_CELOFAN
    ESTAMPAS
    LISTONES
  )

  def packaging_code?(code) when is_binary(code), do: code in @packaging_codes

  @doc """
  Return the recipe for a given product as a list of maps.
  Quantities are in the ingredient's unit (e.g. g, ml, units).

  If a date is provided, returns the active recipe for that date.
  If no date is provided or no recipe is found, falls back to hardcoded recipes.
  """
  def recipe_for_product(%Product{} = product, date \\ nil) do
    # Try to get recipe from database first
    case get_active_recipe(product, date) do
      nil ->
        # Fallback to hardcoded recipes for backward compatibility
        fallback_recipe_for_product(product)

      recipe ->
        # Convert recipe lines to the expected format
        recipe
        |> Repo.preload(:recipe_lines)
        |> Map.get(:recipe_lines, [])
        |> Enum.map(fn line ->
          %{
            ingredient_code: line.ingredient_code,
            quantity: Decimal.to_float(line.quantity)
          }
        end)
    end
  end

  @doc """
  Get the active recipe for a product on a given date.
  Returns the recipe with the most recent effective_date <= date.
  If date is nil, returns the most recent recipe.
  """
  def get_active_recipe(%Product{} = product, date \\ nil) do
    query =
      from r in Recipe,
        where: r.product_id == ^product.id,
        order_by: [desc: r.effective_date],
        limit: 1

    query =
      if date do
        from r in query,
          where: r.effective_date <= ^date
      else
        query
      end

    Repo.one(query)
  end

  @doc """
  List the most recent recipe for each product, ordered by effective_date descending.
  Only shows the latest version of each recipe (hides deprecated/older versions).
  """
  def list_recipes do
    # Find the most recent effective_date for each product
    latest_dates =
      from r in Recipe,
        group_by: r.product_id,
        select: %{
          product_id: r.product_id,
          max_date: max(r.effective_date)
        }

    # Get recipes that match the latest date for each product
    from(r in Recipe,
      inner_join: latest in subquery(latest_dates),
      on: r.product_id == latest.product_id and r.effective_date == latest.max_date,
      order_by: [desc: r.effective_date],
      preload: [:product, :recipe_lines]
    )
    |> Repo.all()
  end

  @doc """
  List all recipes for a product, ordered by effective_date descending.
  """
  def list_recipes_for_product(%Product{} = product) do
    from(r in Recipe,
      where: r.product_id == ^product.id,
      order_by: [desc: r.effective_date],
      preload: :recipe_lines
    )
    |> Repo.all()
  end

  @doc """
  Get all recipe versions grouped by product_id.
  Returns a map where keys are product_ids and values are lists of recipes.
  """
  def list_all_recipe_versions_by_product do
    from(r in Recipe,
      order_by: [r.product_id, desc: r.effective_date],
      preload: [:product, :recipe_lines]
    )
    |> Repo.all()
    |> Enum.group_by(& &1.product_id)
  end

  @doc """
  Get a recipe by ID with preloaded recipe lines and product.
  """
  def get_recipe!(id) do
    Recipe
    |> Repo.get!(id)
    |> Repo.preload([:recipe_lines, :product])
  end

  @doc """
  Create a new recipe with its lines.
  """
  def create_recipe(attrs \\ %{}) do
    %Recipe{}
    |> Recipe.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update a recipe and its lines.
  """
  def update_recipe(%Recipe{} = recipe, attrs) do
    recipe
    |> Recipe.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Delete a recipe.
  """
  def delete_recipe(%Recipe{} = recipe) do
    Repo.delete(recipe)
  end

  @doc """
  Returns a changeset for a recipe.
  """
  def change_recipe(%Recipe{} = recipe, attrs \\ %{}) do
    Recipe.changeset(recipe, attrs)
  end

  @doc """
  Copy a recipe from one product to another.
  Creates a new recipe for the target product with the same recipe lines.
  """
  def copy_recipe_from_product(%Product{} = source_product, %Product{} = target_product, effective_date \\ Date.utc_today()) do
    case get_active_recipe(source_product) do
      nil ->
        {:error, :no_recipe_found}

      source_recipe ->
        source_recipe = Repo.preload(source_recipe, :recipe_lines)

        recipe_attrs = %{
          product_id: target_product.id,
          effective_date: effective_date,
          name: source_recipe.name || "#{target_product.name} Recipe",
          description: source_recipe.description || "Recipe copied from #{source_product.name}",
          recipe_lines:
            Enum.map(source_recipe.recipe_lines || [], fn line ->
              %{
                ingredient_code: line.ingredient_code,
                quantity: Decimal.to_string(line.quantity)
              }
            end)
        }

        create_recipe(recipe_attrs)
    end
  end

  @doc """
  Get options for products that have recipes, for use in dropdowns.
  Returns a list of {label, product_id} tuples.
  """
  def products_with_recipes_select_options do
    from(r in Recipe,
      distinct: r.product_id,
      join: p in assoc(r, :product),
      order_by: p.name,
      select: {p.id, p.name, p.sku}
    )
    |> Repo.all()
    |> Enum.map(fn {id, name, sku} ->
      label =
        if sku do
          "#{name} (#{sku})"
        else
          name
        end

      {label, id}
    end)
  end

  @doc """
  Calculates the estimated total cost of a recipe based on average unit prices of ingredients.
  Returns the total cost in cents.
  Returns {:ok, total_cents} if all ingredients have costs.
  Returns {:partial, total_cents, missing_ingredients} if some ingredients are missing costs.
  """
  def estimated_recipe_cost(%Recipe{} = recipe) do
    recipe = Repo.preload(recipe, :recipe_lines)
    ingredient_infos = Inventory.ingredient_quick_infos()

    {total_cents, missing} =
      recipe.recipe_lines
      |> Enum.reduce({0, []}, fn line, {acc_cents, missing_acc} ->
        ingredient_code = line.ingredient_code
        quantity_decimal = line.quantity

        case Map.get(ingredient_infos, ingredient_code) do
          nil ->
            # Ingredient not found in quick infos
            {acc_cents, [ingredient_code | missing_acc]}

          %{"avg_cost_cents" => nil} ->
            # Ingredient exists but no average cost available
            {acc_cents, [ingredient_code | missing_acc]}

          %{"avg_cost_cents" => avg_cost_cents} when is_integer(avg_cost_cents) ->
            # Calculate cost: avg_cost_cents (cents per unit) * quantity (in ingredient's unit)
            quantity_float = Decimal.to_float(quantity_decimal)
            line_cost_cents = trunc(avg_cost_cents * quantity_float)
            {acc_cents + line_cost_cents, missing_acc}

          _ ->
            {acc_cents, missing_acc}
        end
      end)

    if missing == [] do
      {:ok, total_cents}
    else
      {:partial, total_cents, missing}
    end
  end

  # Fallback to hardcoded recipes (original implementation)
  defp fallback_recipe_for_product(%Product{} = product) do
    main_ingredients =
      case product.sku do
        "TAKIS-GRANDE" -> [%{ingredient_code: "TAKIS_FUEGO", quantity: 1020}]
        "TAKIS-MEDIANA" -> [%{ingredient_code: "TAKIS_FUEGO", quantity: 517}]
        "RUNNERS-GRANDE" -> [%{ingredient_code: "RUNNERS", quantity: 840}]
        "RUNNERS-MEDIANA" -> [%{ingredient_code: "RUNNERS", quantity: 447}]
        "MIXTA-GRANDE" -> [
          %{ingredient_code: "TAKIS_FUEGO", quantity: 340},
          %{ingredient_code: "RUNNERS", quantity: 280},
          %{ingredient_code: "CHIPS_FUEGO", quantity: 160},
        ]
        "MIXTA-MEDIANA" -> [
          %{ingredient_code: "TAKIS_FUEGO", quantity: 225},
          %{ingredient_code: "RUNNERS", quantity: 124},
          %{ingredient_code: "CHIPS_FUEGO", quantity: 77},
        ]
        "SALSA-NEGRAS-GRANDE" -> [
          %{ingredient_code: "CRUJIENTES_INGLESA", quantity: 240},
          %{ingredient_code: "DORITOS_INCOGNITA", quantity: 223},
          %{ingredient_code: "CACAHUATES_INGLESA", quantity: 160},
        ]
        "SALSA-NEGRAS-MEDIANA" -> [
          %{ingredient_code: "CRUJIENTES_INGLESA", quantity: 160},
          %{ingredient_code: "DORITOS_INCOGNITA", quantity: 178},
          %{ingredient_code: "CACAHUATES_INGLESA", quantity: 160},
        ]

        _ -> []
      end

    extra_ingredients =
      cond do
        product.sku == "SALSA-NEGRAS-GRANDE" -> [
          %{ingredient_code: "MIEL_KARO", quantity: 180},
          %{ingredient_code: "MAGGI", quantity: 5}, #ml
          %{ingredient_code: "TAJIN", quantity: 30},
          %{ingredient_code: "LIMON", quantity: 1},
          %{ingredient_code: "PULPARINDIO", quantity: 2},
        ]
        product.sku == "SALSA-NEGRAS-MEDIANA" -> [
          %{ingredient_code: "MIEL_KARO", quantity: 100},
          %{ingredient_code: "MAGGI", quantity: 5},
          %{ingredient_code: "TAJIN", quantity: 15},
          %{ingredient_code: "LIMON", quantity: 0.5},
          %{ingredient_code: "PULPARINDIO", quantity: 1},

        ]
        product.sku in ["TAKIS-GRANDE", "RUNNERS-GRANDE", "MIXTA-GRANDE"] -> [
          %{ingredient_code: "MIEL_KARO", quantity: 180}, #ml
          %{ingredient_code: "SIRILO", quantity: 120}, #ml
          %{ingredient_code: "MIGUELITO", quantity: 30}, #g
          %{ingredient_code: "TAJIN", quantity: 30}, #g
          %{ingredient_code: "LIMON", quantity: 1}, #unit
          %{ingredient_code: "PULPARINDIO", quantity: 2}, #unit
        ]
        product.sku in ["TAKIS-MEDIANA", "RUNNERS-MEDIANA", "MIXTA-MEDIANA"] -> [
          %{ingredient_code: "MIEL_KARO", quantity: 100},
          %{ingredient_code: "SIRILO", quantity: 30},
          %{ingredient_code: "MIGUELITO", quantity: 15},
          %{ingredient_code: "TAJIN", quantity: 15},
          %{ingredient_code: "LIMON", quantity: 0.5},
          %{ingredient_code: "PULPARINDIO", quantity: 1},
        ]
        true -> []
      end

    packing_ingredients = [
      %{ingredient_code: "BOLSA_CELOFAN", quantity: 1}, #unit
      %{ingredient_code: "ESTAMPAS", quantity: 1}, #unit
      %{ingredient_code: "LISTONES", quantity: 15}, #cm
    ] ++
      cond do
        String.contains?(product.sku, "GRANDE") -> [%{ingredient_code: "BASE_GRANDE", quantity: 1}] #unit
        String.contains?(product.sku, "MEDIANA") -> [%{ingredient_code: "BASE_MEDIANA", quantity: 1}] #unit
        true -> []
      end

    main_ingredients ++ extra_ingredients ++ packing_ingredients
  end
end
