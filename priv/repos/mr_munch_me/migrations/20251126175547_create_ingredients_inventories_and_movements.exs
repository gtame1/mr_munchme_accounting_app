defmodule Ledgr.Repo.Migrations.CreateIngredientsInventoriesAndMovements do
  use Ecto.Migration

  def change do
    # ---------- Ingredients ----------
    create table(:ingredients) do
      add :code, :string, null: false   # e.g. "FLOUR", "SUGAR", "BUTTER"
      add :name, :string, null: false   # full name: "Wheat Flour"
      add :unit, :string, null: false, default: "g"  # "g", "ml", "unit", etc.
      add :cost_per_unit_cents, :integer, null: false, default: 0

      timestamps()
    end

    create unique_index(:ingredients, [:code])

  # ---------- Inventory Locations ----------
    create table(:inventory_locations) do
      add :code, :string, null: false   # "MAIN_KITCHEN", "FREEZER", "WAREHOUSE"
      add :name, :string, null: false
      add :description, :text

      timestamps()
    end

    create unique_index(:inventory_locations, [:code])

  # ---------- Inventories ----------
    create table(:inventories) do
      add :ingredient_id, references(:ingredients, on_delete: :delete_all), null: false
      add :location_id, references(:inventory_locations, on_delete: :delete_all), null: false

      add :quantity_on_hand, :integer, null: false, default: 0
      add :avg_cost_per_unit_cents, :integer, null: false, default: 0

      timestamps()
    end

    create unique_index(:inventories, [:ingredient_id, :location_id])

  # ---------- Inventory Movements ----------
    create table(:inventory_movements) do
      add :ingredient_id, references(:ingredients, on_delete: :restrict), null: false

      add :from_location_id, references(:inventory_locations)
      add :to_location_id, references(:inventory_locations)

      add :quantity, :integer, null: false    # always positive
      add :movement_type, :string, null: false  # "purchase", "usage", "transfer", "adjustment"

      add :unit_cost_cents, :integer, null: false, default: 0
      add :total_cost_cents, :integer, null: false, default: 0

      add :source_type, :string       # "order", "expense", "manual"
      add :source_id, :integer
      add :note, :text

      timestamps(updated_at: false)
    end

    create index(:inventory_movements, [:ingredient_id])
    create index(:inventory_movements, [:from_location_id])
    create index(:inventory_movements, [:to_location_id])
    create index(:inventory_movements, [:source_type, :source_id])
  end
end
