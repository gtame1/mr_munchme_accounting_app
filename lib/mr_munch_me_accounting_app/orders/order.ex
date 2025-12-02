defmodule MrMunchMeAccountingApp.Orders.Order do
  use Ecto.Schema
  import Ecto.Changeset

  alias MrMunchMeAccountingApp.Orders.Product
  alias MrMunchMeAccountingApp.Inventory.Location


  @statuses ~w(new_order in_prep ready delivered canceled)
  @delivery_types ~w(pickup delivery)

  schema "orders" do
    field :customer_name, :string
    field :customer_email, :string
    field :customer_phone, :string

    field :delivery_type, :string
    field :delivery_address, :string
    field :delivery_date, :date
    field :delivery_time, :time

    field :status, :string, default: "new_order"
    field :customer_paid_shipping, :boolean, default: false

    belongs_to :product, Product
    belongs_to :prep_location, Location

    timestamps()
  end

  def changeset(order, attrs) do
    order
    |> cast(attrs, [
      :customer_name,
      :customer_email,
      :customer_phone,
      :delivery_type,
      :delivery_address,
      :delivery_date,
      :delivery_time,
      :status,
      :product_id,
      :prep_location_id,
      :customer_paid_shipping
    ])
    |> validate_required([
      :customer_name,
      :customer_phone,
      :delivery_type,
      :delivery_date,
      :product_id,
      :prep_location_id,
      :customer_paid_shipping
    ])
    |> validate_inclusion(:delivery_type, @delivery_types)
    |> validate_inclusion(:status, @statuses)
    |> assoc_constraint(:product)
    |> assoc_constraint(:prep_location)
  end
end
