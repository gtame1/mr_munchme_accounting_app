defmodule Ledgr.Repo.Migrations.AddIsCogsToAccounts do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :is_cogs, :boolean, default: false, null: false
    end

    # Set is_cogs = true for existing COGS accounts (5000, 5010)
    execute(
      "UPDATE accounts SET is_cogs = true WHERE code IN ('5000', '5010')",
      "UPDATE accounts SET is_cogs = false WHERE code IN ('5000', '5010')"
    )
  end
end
