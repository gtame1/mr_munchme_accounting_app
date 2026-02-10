defmodule Ledgr.Repo.Migrations.CreateExpenses do
  use Ecto.Migration

  def change do
    create table(:expenses) do
      add :date, :date, null: false
      add :description, :text, null: false
      add :amount_cents, :integer, null: false
      add :expense_account_id, references(:accounts, on_delete: :restrict), null: false #(e.g. “Rent”, “Marketing”, “Utilities”)
      add :paid_from_account_id, references(:accounts, on_delete: :restrict), null: false # (e.g. Cash, Bank, Credit Card)
      add :category, :string

      timestamps()
    end

    create index(:expenses, [:date])
    create index(:expenses, [:expense_account_id])
    create index(:expenses, [:paid_from_account_id])
  end
end
