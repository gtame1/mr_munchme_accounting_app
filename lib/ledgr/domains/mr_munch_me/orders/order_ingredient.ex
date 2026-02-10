defmodule Ledgr.Domains.MrMunchMe.Orders.OrderIngredient do
  use Ecto.Schema
  import Ecto.Changeset

  schema "order_ingredients" do
    field :ingredient_code, :string
    field :quantity, :decimal
    field :location_code, :string
    belongs_to :order, Ledgr.Domains.MrMunchMe.Orders.Order, on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(order_ingredient, attrs) do
    order_ingredient
    |> cast(attrs, [:order_id, :ingredient_code, :quantity, :location_code])
    |> validate_required([:order_id, :ingredient_code, :quantity, :location_code])
    |> validate_number(:quantity, greater_than: 0)
  end
end
