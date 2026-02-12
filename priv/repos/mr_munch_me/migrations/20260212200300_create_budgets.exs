defmodule Ledgr.Repo.Migrations.CreateBudgets do
  use Ecto.Migration

  def change do
    create table(:budgets) do
      add :year, :integer, null: false
      add :month, :integer, null: false
      add :amount_cents, :integer, null: false, default: 0
      add :account_id, references(:accounts, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:budgets, [:account_id, :year, :month])
    create index(:budgets, [:year, :month])
  end
end
