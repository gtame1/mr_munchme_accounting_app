alias MrMunchMeAccountingApp.Repo
alias MrMunchMeAccountingApp.Accounting.Account
alias MrMunchMeAccountingApp.Orders.Product

alias MrMunchMeAccountingApp.Inventory.{Ingredient, Location, Recipe, RecipeLine}
alias MrMunchMeAccountingApp.Partners.Partner


defmodule SeedHelper do
  def upsert_account(attrs) do
    code = attrs.code

    case Repo.get_by(Account, code: code) do
      nil ->
        %Account{}
        |> Account.changeset(attrs)
        |> Repo.insert!()

      _existing ->
        :ok
    end
  end

  def upsert_product(attrs) do
    sku = attrs.sku

    case Repo.get_by(Product, sku: sku) do
      nil ->
        %Product{}
        |> Product.changeset(attrs)
        |> Repo.insert!()

      _existing ->
        :ok
    end
  end

  def upsert_ingredient(attrs) do
    code = attrs.code

    case Repo.get_by(Ingredient, code: code) do
      nil ->
        %Ingredient{}
        |> Ingredient.changeset(attrs)
        |> Repo.insert!()

      _existing -> :ok
    end
  end

  def upsert_location(attrs) do
    code = attrs.code

    case Repo.get_by(Location, code: code) do
      nil ->
        %Location{}
        |> Location.changeset(attrs)
        |> Repo.insert!()

      _existing -> :ok
    end
  end

  def upsert_partner(attrs) do
    email = attrs.email

    case Repo.get_by(Partner, email: email) do
      nil ->
        %Partner{}
        |> Partner.changeset(attrs)
        |> Repo.insert!()
      _existing -> :ok
    end
  end

  def upsert_recipe(product_sku, effective_date, recipe_lines) do
    product = Repo.get_by!(Product, sku: product_sku)

    recipe_attrs = %{
      product_id: product.id,
      effective_date: effective_date,
      name: "#{product.name} Recipe",
      description: "Initial recipe for #{product.name}"
    }

    case Repo.get_by(Recipe, product_id: product.id, effective_date: effective_date) do
      nil ->
        recipe =
          %Recipe{}
          |> Recipe.changeset(recipe_attrs)
          |> Repo.insert!()

        # Insert recipe lines
        Enum.each(recipe_lines, fn line ->
          %RecipeLine{}
          |> RecipeLine.changeset(%{
            ingredient_code: line.ingredient_code,
            quantity: Decimal.new(to_string(line.quantity))
          })
          |> Ecto.Changeset.put_change(:recipe_id, recipe.id)
          |> Repo.insert!()
        end)

        recipe

      existing ->
        existing
    end
  end
end


# -------------------------
# ASSETS
# -------------------------

assets = [
  %{code: "1000", name: "Cash Ana Gaby", type: "asset", normal_balance: "debit", is_cash: true},
  %{code: "1001", name: "Cash Fernanda Gonzalo", type: "asset", normal_balance: "debit", is_cash: true},
  %{code: "1010", name: "NuBank Ana Gaby Account", type: "asset", normal_balance: "debit", is_cash: true},
  %{code: "1011", name: "Banco Fer", type: "asset", normal_balance: "debit", is_cash: true},
  %{code: "1100", name: "Accounts Receivable (Unpaid Orders)", type: "asset", normal_balance: "debit"},
  %{code: "1100", name: "Orders Paid By Company", type: "asset", normal_balance: "credit"}, # Antiasset, discounted by value paid by company

  # Inventory
  %{code: "1200", name: "Ingredients Inventory", type: "asset", normal_balance: "debit"},
  %{code: "1210", name: "Packaging Inventory", type: "asset", normal_balance: "debit"},
  %{code: "1220", name: "Ingredients Inventory (WIP)", type: "asset", normal_balance: "debit"},

  # Fixed assets
  %{code: "1300", name: "Kitchen Equipment", type: "asset", normal_balance: "debit"},
]

# -------------------------
# LIABILITIES
# -------------------------

liabilities = [
  %{code: "2000", name: "Accounts Payable (General)", type: "liability", normal_balance: "credit"},
  %{code: "2001", name: "Accounts Payable - Ana Gaby", type: "liability", normal_balance: "credit"},
  %{code: "2002", name: "Accounts Payable - Fer", type: "liability", normal_balance: "credit"},
  %{code: "2003", name: "Accounts Payable - Gaby Vera", type: "liability", normal_balance: "credit"},
  %{code: "2011", name: "NuBank AG (CC)", type: "liability", normal_balance: "credit"},
  %{code: "2012", name: "Plata AG (CC)", type: "liability", normal_balance: "credit"},
  %{code: "2013", name: "Nelo Guillo (CC)", type: "liability", normal_balance: "credit"},
  %{code: "2014", name: "Tarjeta de Fer (CC)", type: "liability", normal_balance: "credit"},

  %{code: "2200", name: "Customer Deposits / Unearned Revenue", type: "liability", normal_balance: "credit"},
  %{code: "2100", name: "Sales Tax Payable", type: "liability", normal_balance: "credit"}
]

# -------------------------
# EQUITY
# -------------------------

equity = [
  %{code: "3000", name: "Owner's Equity", type: "equity", normal_balance: "credit"},
  %{code: "3100", name: "Owner's Drawings", type: "equity", normal_balance: "debit"}
]

# -------------------------
# REVENUE
# -------------------------

revenue = [
  %{code: "4000", name: "Sales", type: "revenue", normal_balance: "credit"},
]

# -------------------------
# COST OF GOODS SOLD (COGS)
# -------------------------

cogs = [
  %{code: "5000", name: "Ingredients Used (COGS)", type: "expense", normal_balance: "debit"},
  %{code: "5010", name: "Packaging Used (COGS)", type: "expense", normal_balance: "debit"},
]

# -------------------------
# OPERATING EXPENSES
# -------------------------

expenses = [
  %{code: "6010", name: "Inventory Purchase Shipping Expense", type: "expense", normal_balance: "debit"},
  %{code: "6020", name: "Delivery Expense", type: "expense", normal_balance: "debit"},
  %{code: "6030", name: "Advertising & Marketing", type: "expense", normal_balance: "debit"},
  %{code: "6040", name: "Test Inventory", type: "expense", normal_balance: "debit"},
  %{code: "6050", name: "Parking", type: "expense", normal_balance: "debit"},
  %{code: "6060", name: "Inventory Waste & Shrinkage", type: "expense", normal_balance: "debit"},
  %{code: "6099", name: "Other Expenses", type: "expense", normal_balance: "debit"},
]

(accounts = assets ++ liabilities ++ equity ++ revenue ++ cogs ++ expenses)
|> Enum.each(&SeedHelper.upsert_account/1)

IO.puts("✅ Seeded #{length(accounts)} accounts")


# -------------------------
# PRODUCTS
# -------------------------

products = [
  %{name: "Takis Grande", sku: "TAKIS-GRANDE", price_cents: 58000, active: true},
  %{name: "Takis Mediana", sku: "TAKIS-MEDIANA", price_cents: 45000, active: true},
  %{name: "Runners Grande", sku: "RUNNERS-GRANDE", price_cents: 55000, active: true},
  %{name: "Runners Mediana", sku: "RUNNERS-MEDIANA", price_cents: 42000, active: true},
  %{name: "Mixta Grande", sku: "MIXTA-GRANDE", price_cents: 55000, active: true},
  %{name: "Mixta Mediana", sku: "MIXTA-MEDIANA", price_cents: 42000, active: true},
  %{name: "Salsas Negras Grande", sku: "SALSA-NEGRAS-GRANDE", price_cents: 55000, active: true},
  %{name: "Salsas Negras Mediana", sku: "SALSA-NEGRAS-MEDIANA", price_cents: 42000, active: true},
  %{name: "Envio", sku: "ENVIO", price_cents: 5000, active: true}
]

products
|> Enum.each(&SeedHelper.upsert_product/1)

IO.puts("✅ Seeded #{length(products)} products")


# -------------------------
# INGREDIENTS
# -------------------------

ingredients = [
  %{code: "TAKIS_FUEGO", name: "Takis Fuego", unit: "g", cost_per_unit_cents: 24, inventory_type: "ingredients"},
  %{code: "RUNNERS", name: "Runners", unit: "g", cost_per_unit_cents: 19, inventory_type: "ingredients"},
  %{code: "CHIPS_FUEGO", name: "Chips Fuego", unit: "g", cost_per_unit_cents: 38, inventory_type: "ingredients"},
  %{code: "CRUJIENTES_INGLESA", name: "Crujientes Inglesa", unit: "g", cost_per_unit_cents: 38, inventory_type: "ingredients"},
  %{code: "DORITOS_INCOGNITA", name: "Doritos Incognita", unit: "g", cost_per_unit_cents: 27, inventory_type: "ingredients"},
  %{code: "CACAHUATES_INGLESA", name: "Cacahuates Inglesa", unit: "g", cost_per_unit_cents: 18, inventory_type: "ingredients"},
  %{code: "MIEL_KARO", name: "Miel Karo", unit: "ml", cost_per_unit_cents: 18, inventory_type: "ingredients"},
  %{code: "SIRILO", name: "Sirilo", unit: "ml", cost_per_unit_cents: 29, inventory_type: "ingredients"},
  %{code: "MIGUELITO", name: "Miguelito", unit: "g", cost_per_unit_cents: 14, inventory_type: "ingredients"},
  %{code: "TAJIN", name: "Tajin", unit: "g", cost_per_unit_cents: 20, inventory_type: "ingredients"},
  %{code: "LIMON", name: "Limon", unit: "unit", cost_per_unit_cents: 87, inventory_type: "ingredients"},
  %{code: "PULPARINDIO", name: "Pulparindio", unit: "unit", cost_per_unit_cents: 26, inventory_type: "ingredients"},
  %{code: "MAGGI", name: "Maggi", unit: "ml", cost_per_unit_cents: 41, inventory_type: "ingredients"},
  %{code: "BOLSA_CELOFAN", name: "Bolsa Celofan", unit: "unit", cost_per_unit_cents: 416, inventory_type: "packing"},
  %{code: "ESTAMPAS", name: "Estampas", unit: "unit", cost_per_unit_cents: 682, inventory_type: "packing"},
  %{code: "LISTONES", name: "Listones", unit: "cm", cost_per_unit_cents: 13, inventory_type: "packing"},
  %{code: "MOLDE_GRANDE", name: "Molde Grande", unit: "unit", cost_per_unit_cents: 10000, inventory_type: "kitchen"},
  %{code: "MOLDE_MEDIANO", name: "Molde Mediana", unit: "unit", cost_per_unit_cents: 500, inventory_type: "kitchen"},
  %{code: "BASE_GRANDE", name: "Base Grande", unit: "unit", cost_per_unit_cents: 1844, inventory_type: "packing"},
  %{code: "BASE_MEDIANA", name: "Base Mediana", unit: "unit", cost_per_unit_cents: 1477, inventory_type: "packing"},
]

ingredients
|> Enum.each(&SeedHelper.upsert_ingredient/1)

IO.puts("✅ Seeded #{length(ingredients)} ingredients")

# -------------------------
# Inventory locations
# -------------------------

locations = [
  %{code: "CASA_AG", name: "Casa Ana Gaby", description: "Cocina principal de Ana Gaby"},
  %{code: "CASA_FG", name: "Casa Fernanda Gonzalo", description: "Cocina principal de Fernanda Gonzalo"},
]

locations
|> Enum.each(&SeedHelper.upsert_location/1)

IO.puts("✅ Seeded #{length(locations)} locations")


# -------------------------
# Partners
# -------------------------

partners = [
  %{name: "Ana Gabriela Vazquez", email: "anag997@hotmail.com", phone: "5543417149"},
  %{name: "Fernanda Gonzalo", email: "marifergonzalo@gmail.com", phone: "5579184041"},
]

partners
|> Enum.each(&SeedHelper.upsert_partner/1)

IO.puts("✅ Seeded #{length(partners)} partners")


# -------------------------
# RECIPES
# -------------------------

# Initial recipe date: November 1st, 2025
initial_recipe_date = ~D[2025-11-01]

# Helper function to get recipe lines for a product SKU
get_recipe_lines = fn sku ->
  main_ingredients =
    case sku do
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
      sku == "SALSA-NEGRAS-GRANDE" -> [
        %{ingredient_code: "MIEL_KARO", quantity: 180},
        %{ingredient_code: "MAGGI", quantity: 5},
        %{ingredient_code: "TAJIN", quantity: 30},
        %{ingredient_code: "LIMON", quantity: 1},
        %{ingredient_code: "PULPARINDIO", quantity: 2},
      ]
      sku == "SALSA-NEGRAS-MEDIANA" -> [
        %{ingredient_code: "MIEL_KARO", quantity: 100},
        %{ingredient_code: "MAGGI", quantity: 5},
        %{ingredient_code: "TAJIN", quantity: 15},
        %{ingredient_code: "LIMON", quantity: 0.5},
        %{ingredient_code: "PULPARINDIO", quantity: 1},
      ]
      sku in ["TAKIS-GRANDE", "RUNNERS-GRANDE", "MIXTA-GRANDE"] -> [
        %{ingredient_code: "MIEL_KARO", quantity: 180},
        %{ingredient_code: "SIRILO", quantity: 120},
        %{ingredient_code: "MIGUELITO", quantity: 30},
        %{ingredient_code: "TAJIN", quantity: 30},
        %{ingredient_code: "LIMON", quantity: 1},
        %{ingredient_code: "PULPARINDIO", quantity: 2},
      ]
      sku in ["TAKIS-MEDIANA", "RUNNERS-MEDIANA", "MIXTA-MEDIANA"] -> [
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
    %{ingredient_code: "BOLSA_CELOFAN", quantity: 1},
    %{ingredient_code: "ESTAMPAS", quantity: 1},
    %{ingredient_code: "LISTONES", quantity: 15},
  ] ++
    cond do
      String.contains?(sku, "GRANDE") -> [%{ingredient_code: "BASE_GRANDE", quantity: 1}]
      String.contains?(sku, "MEDIANA") -> [%{ingredient_code: "BASE_MEDIANA", quantity: 1}]
      true -> []
    end

  main_ingredients ++ extra_ingredients ++ packing_ingredients
end

# Seed recipes for all products (except ENVIO which doesn't have a recipe)
recipe_skus = [
  "TAKIS-GRANDE",
  "TAKIS-MEDIANA",
  "RUNNERS-GRANDE",
  "RUNNERS-MEDIANA",
  "MIXTA-GRANDE",
  "MIXTA-MEDIANA",
  "SALSA-NEGRAS-GRANDE",
  "SALSA-NEGRAS-MEDIANA"
]

recipe_count =
  recipe_skus
  |> Enum.map(fn sku ->
    recipe_lines = get_recipe_lines.(sku)
    SeedHelper.upsert_recipe(sku, initial_recipe_date, recipe_lines)
    length(recipe_lines)
  end)
  |> Enum.sum()

IO.puts("✅ Seeded #{length(recipe_skus)} recipes with #{recipe_count} total recipe lines")
