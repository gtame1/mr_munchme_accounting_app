defmodule Ledgr.Domains.MrMunchMe.Inventory.PurchaseForm do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :ingredient_code, :string
    field :location_code, :string
    field :quantity, :integer
    field :total_cost_pesos, :decimal
    field :paid_from_account_id, :string
    field :purchase_date, :date
    field :notes, :string
  end

  def changeset(form, attrs) do
    form
    |> cast(attrs, [
      :ingredient_code,
      :location_code,
      :quantity,
      :total_cost_pesos,
      :paid_from_account_id,
      :purchase_date,
      :notes
    ])
    |> validate_required([
      :ingredient_code,
      :location_code,
      :quantity,
      :total_cost_pesos,
      :paid_from_account_id,
      :purchase_date
    ])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:total_cost_pesos, greater_than: 0)
  end
end
