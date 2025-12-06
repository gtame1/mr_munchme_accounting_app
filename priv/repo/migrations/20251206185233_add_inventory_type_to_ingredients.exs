defmodule MrMunchMeAccountingApp.Repo.Migrations.AddInventoryTypeToIngredients do
  use Ecto.Migration

  def change do
    alter table(:ingredients) do
      add :inventory_type, :string, null: false, default: "ingredients"
    end

    create index(:ingredients, [:inventory_type])
  end
end
