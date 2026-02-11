alias Ledgr.Repo
alias Ledgr.Core.Accounting.Account

# ── Viaxe Chart of Accounts ──────────────────────────────────

viaxe_accounts = [
  # Assets
  %{code: "1000", name: "Cash", type: "asset", normal_balance: "debit", is_cash: true},
  %{code: "1010", name: "Bank Account", type: "asset", normal_balance: "debit", is_cash: true},
  %{code: "1100", name: "Accounts Receivable", type: "asset", normal_balance: "debit"},

  # Liabilities
  %{code: "2100", name: "Supplier Payables", type: "liability", normal_balance: "credit"},
  %{code: "2200", name: "Customer Deposits", type: "liability", normal_balance: "credit"},

  # Revenue
  %{code: "4000", name: "Commission Revenue", type: "revenue", normal_balance: "credit"},
  %{code: "4100", name: "Service Fees", type: "revenue", normal_balance: "credit"},

  # Cost of Goods Sold
  %{code: "5000", name: "Booking COGS", type: "expense", normal_balance: "debit", is_cogs: true},

  # Operating Expenses
  %{code: "6000", name: "Office Rent", type: "expense", normal_balance: "debit"},
  %{code: "6010", name: "Utilities", type: "expense", normal_balance: "debit"},
  %{code: "6020", name: "Marketing & Advertising", type: "expense", normal_balance: "debit"},
  %{code: "6030", name: "Travel & Entertainment", type: "expense", normal_balance: "debit"},
  %{code: "6040", name: "Software & Subscriptions", type: "expense", normal_balance: "debit"},
  %{code: "6050", name: "Insurance", type: "expense", normal_balance: "debit"},
  %{code: "6060", name: "Professional Services", type: "expense", normal_balance: "debit"},
  %{code: "6070", name: "Office Supplies", type: "expense", normal_balance: "debit"},
  %{code: "6080", name: "Bank Fees", type: "expense", normal_balance: "debit"},
  %{code: "6090", name: "Miscellaneous Expenses", type: "expense", normal_balance: "debit"},

  # Other Income
  %{code: "4900", name: "Other Income", type: "revenue", normal_balance: "credit"},
]

for attrs <- viaxe_accounts do
  case Repo.get_by(Account, code: attrs.code) do
    nil ->
      %Account{}
      |> Account.changeset(attrs)
      |> Repo.insert!()

    _existing ->
      :ok
  end
end

IO.puts("✅ Seeded #{length(viaxe_accounts)} Viaxe accounts")
