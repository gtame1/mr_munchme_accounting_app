alias MrMunchMeAccountingApp.Repo
alias MrMunchMeAccountingApp.Accounting.Account
alias MrMunchMeAccountingApp.Orders.Product

alias MrMunchMeAccountingApp.Inventory.{Ingredient, Location}
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
  %{code: "2000", name: "Accounts Payable", type: "liability", normal_balance: "credit"},
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
  %{code: "TAKIS_FUEGO", name: "Takis Fuego", unit: "g", cost_per_unit_cents: 24},
  %{code: "RUNNERS", name: "Runners", unit: "g", cost_per_unit_cents: 19},
  %{code: "CHIPS_FUEGO", name: "Chips Fuego", unit: "g", cost_per_unit_cents: 38},
  %{code: "CRUJIENTES_INGLESA", name: "Crujientes Inglesa", unit: "g", cost_per_unit_cents: 38},
  %{code: "DORITOS_INCOGNITA", name: "Doritos Incognita", unit: "g", cost_per_unit_cents: 27},
  %{code: "CACAHUATES_INGLESA", name: "Cacahuates Inglesa", unit: "g", cost_per_unit_cents: 18},
  %{code: "MIEL_KARO", name: "Miel Karo", unit: "ml", cost_per_unit_cents: 18},
  %{code: "SIRILO", name: "Sirilo", unit: "ml", cost_per_unit_cents: 29},
  %{code: "MIGUELITO", name: "Miguelito", unit: "g", cost_per_unit_cents: 14},
  %{code: "TAJIN", name: "Tajin", unit: "g", cost_per_unit_cents: 20},
  %{code: "LIMON", name: "Limon", unit: "unit", cost_per_unit_cents: 87},
  %{code: "PULPARINDIO", name: "Pulparindio", unit: "unit", cost_per_unit_cents: 26},
  %{code: "MAGGI", name: "Maggi", unit: "ml", cost_per_unit_cents: 41},
  %{code: "BOLSA_CELOFAN", name: "Bolsa Celofan", unit: "unit", cost_per_unit_cents: 416},
  %{code: "ESTAMPAS", name: "Estampas", unit: "unit", cost_per_unit_cents: 682},
  %{code: "LISTONES", name: "Listones", unit: "cm", cost_per_unit_cents: 13},
  %{code: "MOLDE_GRANDE", name: "Molde Grande", unit: "unit", cost_per_unit_cents: 10000},
  %{code: "MOLDE_MEDIANO", name: "Molde Mediana", unit: "unit", cost_per_unit_cents: 500},
  %{code: "BASE_GRANDE", name: "Base Grande", unit: "unit", cost_per_unit_cents: 1844},
  %{code: "BASE_MEDIANA", name: "Base Mediana", unit: "unit", cost_per_unit_cents: 1477},
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
  %{name: "Ana Gabriela Vazquez", email: "ana.gaby@example.com", phone: "1234567890"},
  %{name: "Fernanda Gonzalo", email: "fernanda.gonzalo@example.com", phone: "1234567890"},
]

partners
|> Enum.each(&SeedHelper.upsert_partner/1)

IO.puts("✅ Seeded #{length(partners)} partners")
