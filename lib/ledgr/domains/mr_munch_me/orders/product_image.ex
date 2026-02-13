defmodule Ledgr.Domains.MrMunchMe.Orders.ProductImage do
  use Ecto.Schema
  import Ecto.Changeset

  schema "product_images" do
    field :image_url, :string
    field :position, :integer, default: 0

    belongs_to :product, Ledgr.Domains.MrMunchMe.Orders.Product

    timestamps()
  end

  def changeset(product_image, attrs) do
    product_image
    |> cast(attrs, [:image_url, :position, :product_id])
    |> validate_required([:image_url, :product_id])
  end
end
