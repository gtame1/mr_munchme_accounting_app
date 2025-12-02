defmodule MrMunchMeAccountingApp.Repo.Migrations.AddMovementDateToInventoryMovements do
  use Ecto.Migration

  def change do
    alter table(:inventory_movements) do
      add :movement_date, :date, null: false, default: fragment("CURRENT_DATE")
    end
  end
end
