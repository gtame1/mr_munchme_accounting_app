defmodule Ledgr.Domains.Viaxe.Bookings.Booking do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Domains.Viaxe.Customers.Customer
  alias Ledgr.Domains.Viaxe.Trips.Trip
  alias Ledgr.Domains.Viaxe.Bookings.{BookingItem, BookingPayment, BookingPassenger}

  schema "bookings" do
    belongs_to :customer, Customer
    belongs_to :trip, Trip
    has_many :booking_items, BookingItem
    has_many :booking_payments, BookingPayment
    has_many :booking_passengers, BookingPassenger
    has_many :passengers, through: [:booking_passengers, :customer]

    field :status, :string, default: "draft"
    field :booking_date, :date
    field :travel_date, :date
    field :return_date, :date
    field :destination, :string
    field :booking_type, :string        # flight, hotel, tour, transfer, car_rental, cruise, insurance, other
    field :booking_details, :map        # JSONB with type-specific structured fields
    field :commission_type, :string     # fixed, percentage
    field :commission_value, :integer   # cents if fixed; basis points (×100) if percentage
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
    :trip_id, :travel_date, :return_date, :destination,
    :booking_type, :booking_details, :commission_type, :commission_value,
    :total_cost_cents, :total_price_cents, :commission_cents, :notes
  ]

  @valid_booking_types ~w(flight hotel tour transfer car_rental cruise insurance other)

  def changeset(booking, attrs) do
    booking
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, ~w(draft confirmed in_progress completed canceled))
    |> validate_inclusion(:booking_type, @valid_booking_types)
    |> validate_inclusion(:commission_type, ~w(fixed percentage))
    |> validate_number(:total_cost_cents, greater_than_or_equal_to: 0)
    |> validate_number(:total_price_cents, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:customer_id)
    |> foreign_key_constraint(:trip_id)
    |> calculate_commission()
  end

  @doc "Recalculates totals from booking items; preserves commission type/value"
  def recalculate_totals(booking, items) do
    total_cost = Enum.reduce(items, 0, fn item, acc -> acc + item.cost_cents * item.quantity end)
    total_price = Enum.reduce(items, 0, fn item, acc -> acc + item.price_cents * item.quantity end)

    booking
    |> Ecto.Changeset.change(%{
      total_cost_cents: total_cost,
      total_price_cents: total_price
    })
    |> calculate_commission()
  end

  # Calculates commission_cents from commission_type/value or falls back to price - cost
  defp calculate_commission(changeset) do
    commission_type = get_field(changeset, :commission_type)
    commission_value = get_field(changeset, :commission_value)
    total_price = get_field(changeset, :total_price_cents) || 0

    commission =
      cond do
        commission_type == "fixed" && commission_value ->
          commission_value

        commission_type == "percentage" && commission_value && total_price > 0 ->
          div(total_price * commission_value, 10_000)

        true ->
          # Fallback: price - cost (legacy behavior)
          total_cost = get_field(changeset, :total_cost_cents) || 0
          total_price - total_cost
      end

    put_change(changeset, :commission_cents, max(commission, 0))
  end
end
