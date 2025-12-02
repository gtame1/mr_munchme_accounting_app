defmodule MrMunchMeAccountingApp.Inventory.Recepies do
  @moduledoc """
  Recepies context: recipes for products.
  """
  import Ecto.Query
  alias MrMunchMeAccountingApp.Repo
  alias MrMunchMeAccountingApp.Orders.Product
  alias MrMunchMeAccountingApp.Inventory.{Recipe, RecipeLine}

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
  List all recipes, ordered by effective_date descending.
  """
  def list_recipes do
    from(r in Recipe,
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
  Get a recipe by ID with preloaded recipe lines.
  """
  def get_recipe!(id) do
    Recipe
    |> Repo.get!(id)
    |> Repo.preload(:recipe_lines)
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
