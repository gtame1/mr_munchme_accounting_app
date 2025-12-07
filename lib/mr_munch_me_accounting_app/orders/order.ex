defmodule MrMunchMeAccountingApp.Orders.Order do
  use Ecto.Schema
  import Ecto.Changeset

  alias MrMunchMeAccountingApp.Orders.Product
  alias MrMunchMeAccountingApp.Inventory.Location
  alias MrMunchMeAccountingApp.Customers.Customer


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
    belongs_to :customer, Customer

    has_many :order_ingredients, MrMunchMeAccountingApp.Orders.OrderIngredient, on_replace: :delete

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
      :customer_paid_shipping,
      :customer_id
    ])
    |> validate_required([
      :delivery_type,
      :delivery_date,
      :product_id,
      :prep_location_id,
      :customer_paid_shipping
    ])
    |> validate_customer_info()
    |> validate_inclusion(:delivery_type, @delivery_types)
    |> validate_inclusion(:status, @statuses)
    |> assoc_constraint(:product)
    |> assoc_constraint(:prep_location)
    |> assoc_constraint(:customer)
  end

  # Validates that either customer_id is set OR customer_name and customer_phone are provided
  defp validate_customer_info(changeset) do
    customer_id = get_field(changeset, :customer_id)

    if customer_id do
      # If customer_id is set, that's valid
      changeset
    else
      # Validate that customer_name and customer_phone are provided
      changeset
      |> validate_required([:customer_name, :customer_phone])
    end
  end
end
