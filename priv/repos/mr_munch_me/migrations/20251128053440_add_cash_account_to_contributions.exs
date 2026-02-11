defmodule Ledgr.Repo.Migrations.AddCashAccountToContributions do
  use Ecto.Migration

  def change do
    alter table(:capital_contributions) do
      add :cash_account_id, references(:accounts, on_delete: :nothing)
    end

    create index(:capital_contributions, [:cash_account_id])
  end
end
