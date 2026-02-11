defmodule Ledgr.Domains.Viaxe.Bookings.Booking do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Core.Customers.Customer
  alias Ledgr.Domains.Viaxe.Bookings.{BookingItem, BookingPayment}

  schema "bookings" do
    belongs_to :customer, Customer
    has_many :booking_items, BookingItem
    has_many :booking_payments, BookingPayment

    field :status, :string, default: "draft"
    field :booking_date, :date
    field :travel_date, :date
    field :return_date, :date
    field :passengers, :integer, default: 1
    field :destination, :string
    field :total_cost_cents, :integer, default: 0
    field :total_price_cents, :integer, default: 0
    field :commission_cents, :integer, default: 0
    field :notes, :string

    # Virtual fields
    field :customer_name, :string, virtual: true

    timestamps(type: :utc_datetime)
  end

  @required_fields [:customer_id, :booking_date, :status]
  @optional_fields [
    :travel_date, :return_date, :passengers, :destination,
    :total_cost_cents, :total_price_cents, :commission_cents, :notes
  ]

  def changeset(booking, attrs) do
    booking
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, ~w(draft confirmed in_progress completed canceled))
    |> validate_number(:passengers, greater_than: 0)
    |> validate_number(:total_cost_cents, greater_than_or_equal_to: 0)
    |> validate_number(:total_price_cents, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:customer_id)
  end

  @doc "Recalculates totals from booking items"
  def recalculate_totals(booking, items) do
    total_cost = Enum.reduce(items, 0, fn item, acc -> acc + item.cost_cents * item.quantity end)
    total_price = Enum.reduce(items, 0, fn item, acc -> acc + item.price_cents * item.quantity end)
    commission = total_price - total_cost

    booking
    |> Ecto.Changeset.change(%{
      total_cost_cents: total_cost,
      total_price_cents: total_price,
      commission_cents: commission
    })
  end
end
