defmodule MrMunchMeAccountingApp.Repo.Migrations.AddPaidFromAccountToInventoryMovements do
  use Ecto.Migration

  def change do
    alter table(:inventory_movements) do
      add :paid_from_account_id, references(:accounts, on_delete: :nilify_all)
    end

    create index(:inventory_movements, [:paid_from_account_id])
  end
end
