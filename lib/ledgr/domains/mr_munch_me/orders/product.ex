defmodule Ledgr.Domains.MrMunchMe.Orders.Product do
  use Ecto.Schema
  import Ecto.Changeset

  schema "products" do
    field :name, :string
    field :sku, :string
    field :price_cents, :integer
    field :active, :boolean, default: true

    has_many :orders, Ledgr.Domains.MrMunchMe.Orders.Order

    timestamps()
  end

  def changeset(product, attrs) do
    product
    |> cast(attrs, [:name, :sku, :price_cents, :active])
    |> validate_required([:name, :price_cents])
    |> validate_number(:price_cents, greater_than: 0)
  end
end
