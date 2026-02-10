defmodule Ledgr.Customers.Customer do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Orders.Order

  schema "customers" do
    field :name, :string
    field :email, :string
    field :phone, :string
    field :delivery_address, :string

    has_many :orders, Order

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(customer, attrs) do
    customer
    |> cast(attrs, [:name, :email, :phone, :delivery_address])
    |> validate_required([:name, :phone])
    |> unique_constraint(:phone, message: "a customer with this phone number already exists")
    |> validate_email_format()
  end

  defp validate_email_format(changeset) do
    email = get_field(changeset, :email)

    if email && email != "" do
      validate_format(changeset, :email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email address")
    else
      changeset
    end
  end
end
