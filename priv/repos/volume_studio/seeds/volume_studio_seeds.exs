# Reuses SeedHelper from core_seeds.exs (already loaded)

# ── Volume Studio Accounts ───────────────────────────────────────────────────

accounts = [
  # Assets
  %{code: "1000", name: "Cash", type: "asset", normal_balance: "debit", is_cash: true},
  %{code: "1100", name: "Accounts Receivable", type: "asset", normal_balance: "debit"},
  %{code: "1400", name: "IVA Receivable (Tax Credit)", type: "asset", normal_balance: "debit"},

  # Liabilities
  %{code: "2100", name: "IVA Payable", type: "liability", normal_balance: "credit"},
  %{code: "2200", name: "Deferred Subscription Revenue", type: "liability", normal_balance: "credit"},
  %{code: "2300", name: "Owed Change Payable", type: "liability", normal_balance: "credit"},

  # Revenue
  %{code: "4000", name: "Subscription Revenue", type: "revenue", normal_balance: "credit"},
  %{code: "4010", name: "Class Revenue", type: "revenue", normal_balance: "credit"},
  %{code: "4020", name: "Consultation Revenue", type: "revenue", normal_balance: "credit"},
  %{code: "4030", name: "Space Rental Revenue", type: "revenue", normal_balance: "credit"},

  # Expenses
  %{code: "6010", name: "Instructor Fees", type: "expense", normal_balance: "debit"},
  %{code: "6020", name: "Utilities (Gas, Electricity, Water)", type: "expense", normal_balance: "debit"},
  %{code: "6030", name: "Advertising & Marketing", type: "expense", normal_balance: "debit"},
  %{code: "6040", name: "Equipment & Supplies", type: "expense", normal_balance: "debit"},
  %{code: "6050", name: "Cleaning & Maintenance", type: "expense", normal_balance: "debit"},
  %{code: "6060", name: "Payment Processing Fees", type: "expense", normal_balance: "debit"},
  %{code: "6070", name: "Software & Subscriptions", type: "expense", normal_balance: "debit"},
  %{code: "6080", name: "Permits & Licenses", type: "expense", normal_balance: "debit"},
  %{code: "6090", name: "Insurance", type: "expense", normal_balance: "debit"},
  %{code: "6099", name: "Other Expenses", type: "expense", normal_balance: "debit"},
]

accounts
|> Enum.each(&SeedHelper.upsert_account/1)

IO.puts("✅ Seeded #{length(accounts)} Volume Studio accounts")

# ── Subscription Plans ────────────────────────────────────────────────────────

alias Ledgr.Domains.VolumeStudio.SubscriptionPlans

plans = [
  # ── Paquetes de Clases ─────────────────────────────────────────────────────
  %{name: "1 Clase Muestra",        plan_type: "package",    price_cents: 18_000,     class_limit: 1,   duration_months: nil, duration_days: 5,  description: "Clase de muestra para nuevos miembros."},
  %{name: "1 Clase",                plan_type: "package",    price_cents: 25_000,     class_limit: 1,   duration_months: nil, duration_days: 5},
  %{name: "5 Clases",               plan_type: "package",    price_cents: 115_000,    class_limit: 5,   duration_months: nil, duration_days: 10},
  %{name: "10 Clases",              plan_type: "package",    price_cents: 210_000,    class_limit: 10,  duration_months: nil, duration_days: 15},
  %{name: "15 Clases",              plan_type: "package",    price_cents: 285_000,    class_limit: 15,  duration_months: nil, duration_days: 20},
  # ── Promos Apertura ────────────────────────────────────────────────────────
  %{name: "First Timers (3 Clases)", plan_type: "promo",     price_cents: 66_000,     class_limit: 3,   duration_months: nil, duration_days: nil, description: "Promo apertura: 3 clases para nuevos miembros."},
  %{name: "1 Week Unlimited",        plan_type: "promo",     price_cents: 126_000,    class_limit: nil, duration_months: nil, duration_days: 7,   description: "Promo apertura: clases ilimitadas por 1 semana."},
  # ── Membresías ─────────────────────────────────────────────────────────────
  %{name: "1 Month Unlimited",      plan_type: "membership", price_cents: 450_000,    class_limit: 25,  duration_months: 1,  description: "Incluye 1 Inbody al comprar y al terminar."},
  %{name: "3 Months Unlimited",     plan_type: "membership", price_cents: 1_237_500,  class_limit: 75,  duration_months: 3,  description: "Incluye 3 Inbodys + 1 consulta."},
  %{name: "6 Months Unlimited",     plan_type: "membership", price_cents: 2_250_000,  class_limit: 150, duration_months: 6,  description: "Incluye 6 Inbodys + 3 consultas + 1 café/smoothie mensual."},
  %{name: "1 Year Unlimited",       plan_type: "membership", price_cents: 4_200_000,  class_limit: 300, duration_months: 12, description: "Incluye 1 Inbody + 1 consulta al mes + merch."},
  # ── Servicios Extra ────────────────────────────────────────────────────────
  %{name: "Inbody",                       plan_type: "extra", price_cents: 15_000,  class_limit: nil, duration_months: nil, description: "Análisis de composición corporal."},
  %{name: "Consulta Nutricional Básica",  plan_type: "extra", price_cents: 70_000,  class_limit: nil, duration_months: nil},
  %{name: "Consulta Hormonal Funcional",  plan_type: "extra", price_cents: 100_000, class_limit: nil, duration_months: nil},
]

Enum.each(plans, fn attrs ->
  case SubscriptionPlans.get_plan_by_name(attrs.name) do
    nil ->
      {:ok, _} = SubscriptionPlans.create_subscription_plan(attrs)
    existing ->
      {:ok, _} = SubscriptionPlans.update_subscription_plan(existing, attrs)
  end
end)

IO.puts("✅ Seeded #{length(plans)} Volume Studio subscription plans")
