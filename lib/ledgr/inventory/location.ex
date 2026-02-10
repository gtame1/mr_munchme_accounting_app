defmodule Ledgr.Inventory.Location do
  use Ecto.Schema
  import Ecto.Changeset

  schema "inventory_locations" do
    field :code, :string
    field :name, :string
    field :description, :string

    has_many :inventories, Ledgr.Inventory.InventoryItem

    timestamps()
  end

  def changeset(location, attrs) do
    location
    |> cast(attrs, [:code, :name, :description])
    |> validate_required([:code, :name])
    |> unique_constraint(:code)
  end
end
