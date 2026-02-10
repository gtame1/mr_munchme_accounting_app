defmodule Ledgr.Inventory.Ingredient do
  use Ecto.Schema
  import Ecto.Changeset

  schema "ingredients" do
    field :code, :string
    field :name, :string
    field :unit, :string, default: "g"
    field :cost_per_unit_cents, :integer, default: 0
    field :cost_per_unit_pesos, :string, virtual: true
    field :inventory_type, :string, default: "ingredients"

    has_many :inventories, Ledgr.Inventory.InventoryItem
    has_many :inventory_movements, Ledgr.Inventory.InventoryMovement

    timestamps()
  end

  @inventory_types ~w(ingredients packing kitchen other)

  def changeset(ingredient, attrs) do
    ingredient
    |> cast(attrs, [:code, :name, :unit, :cost_per_unit_cents, :inventory_type])
    |> validate_required([:code, :name, :unit, :cost_per_unit_cents, :inventory_type])
    |> validate_number(:cost_per_unit_cents, greater_than_or_equal_to: 0)
    |> validate_inclusion(:inventory_type, @inventory_types)
    |> unique_constraint(:code)
  end
end
