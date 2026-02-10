defmodule Ledgr.Inventory.InventoryMovement do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Inventory.{Ingredient, Location}
  alias Ledgr.Accounting.Account

  schema "inventory_movements" do
    field :quantity, :integer
    field :movement_type, :string
    field :unit_cost_cents, :integer
    field :total_cost_cents, :integer
    field :source_type, :string
    field :source_id, :integer
    field :note, :string
    field :movement_date, :date

    belongs_to :ingredient, Ingredient
    belongs_to :from_location, Location
    belongs_to :to_location, Location

    belongs_to :paid_from_account, Account

    timestamps(updated_at: false)
  end

  def changeset(movement, attrs) do
    movement
    |> cast(attrs, [
      :ingredient_id,
      :from_location_id,
      :to_location_id,
      :quantity,
      :movement_type,
      :unit_cost_cents,
      :total_cost_cents,
      :source_type,
      :source_id,
      :note,
      :paid_from_account_id,
      :movement_date
    ])
    |> validate_required([:ingredient_id, :quantity, :movement_type, :movement_date])
    |> assoc_constraint(:paid_from_account)
    |> assoc_constraint(:ingredient)
    |> assoc_constraint(:from_location)
    |> assoc_constraint(:to_location)
  end
end
