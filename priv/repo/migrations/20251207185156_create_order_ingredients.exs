defmodule Ledgr.Repo.Migrations.CreateOrderIngredients do
  use Ecto.Migration

  def change do
    create table(:order_ingredients) do
      add :ingredient_code, :string
      add :quantity, :decimal
      add :location_code, :string
      add :order_id, references(:orders, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:order_ingredients, [:order_id])
  end
end
