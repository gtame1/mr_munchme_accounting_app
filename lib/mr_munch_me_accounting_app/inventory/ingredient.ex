defmodule MrMunchMeAccountingApp.Inventory.Ingredient do
  use Ecto.Schema
  import Ecto.Changeset

  schema "ingredients" do
    field :code, :string
    field :name, :string
    field :unit, :string, default: "g"
    field :cost_per_unit_cents, :integer, default: 0

    has_many :inventories, MrMunchMeAccountingApp.Inventory.InventoryItem
    has_many :inventory_movements, MrMunchMeAccountingApp.Inventory.InventoryMovement

    timestamps()
  end

  def changeset(ingredient, attrs) do
    ingredient
    |> cast(attrs, [:code, :name, :unit, :cost_per_unit_cents])
    |> validate_required([:code, :name, :unit, :cost_per_unit_cents])
    |> validate_number(:cost_per_unit_cents, greater_than_or_equal_to: 0)
    |> unique_constraint(:code)
  end
end
