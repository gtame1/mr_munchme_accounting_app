alias Ledgr.Repo
alias Ledgr.Core.Accounting.Account
alias Ledgr.Core.Partners.Partner

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
# CORE ACCOUNTS (shared across domains)
# -------------------------

core_accounts = [
  # Equity
  %{code: "3000", name: "Owner's Equity", type: "equity", normal_balance: "credit"},
  %{code: "3050", name: "Retained Earnings", type: "equity", normal_balance: "credit"},
  %{code: "3100", name: "Owner's Drawings", type: "equity", normal_balance: "debit"},
]

core_accounts
|> Enum.each(&SeedHelper.upsert_account/1)

IO.puts("✅ Seeded #{length(core_accounts)} core accounts")
