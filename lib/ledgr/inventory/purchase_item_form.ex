defmodule Ledgr.Inventory.PurchaseItemForm do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :ingredient_code, :string
    field :quantity, :integer
    field :total_cost_pesos, :decimal
  end

  def changeset(form, attrs) do
    form
    |> cast(attrs, [:ingredient_code, :quantity, :total_cost_pesos])
    |> validate_required([:ingredient_code, :quantity, :total_cost_pesos])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:total_cost_pesos, greater_than: 0)
  end
end
