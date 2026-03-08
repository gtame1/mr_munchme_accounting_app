defmodule Ledgr.Domains.MrMunchMe.Orders.Product do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Domains.MrMunchMe.Orders.ProductImage
  alias Ledgr.Domains.MrMunchMe.Orders.ProductVariant

  schema "products" do
    field :name, :string
    field :active, :boolean, default: true
    field :description, :string
    field :image_url, :string
    field :position, :integer, default: 0
    field :deleted_at, :utc_datetime

    has_many :images, ProductImage, preload_order: [asc: :position]
    has_many :variants, ProductVariant, preload_order: [asc: :inserted_at]

    timestamps()
  end

  def changeset(product, attrs) do
    product
    |> cast(attrs, [:name, :active, :description, :image_url, :position])
    |> validate_required([:name])
  end
end
