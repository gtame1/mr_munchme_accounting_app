defmodule MrMunchMeAccountingApp.Repo.Migrations.AddPerformanceIndexes do
  use Ecto.Migration

  def change do
    # Inventory movements — heavily filtered by movement_type in ~8 locations
    create index(:inventory_movements, [:movement_type])
    create index(:inventory_movements, [:ingredient_id, :movement_type])

    # Journal entries — filtered by entry_type in ~6 locations
    create index(:journal_entries, [:entry_type])
    create index(:journal_entries, [:entry_type, :date])

    # Order payments — foreign key used in joins (if_not_exists in case already created)
    create_if_not_exists index(:order_payments, [:partner_id])
  end
end
