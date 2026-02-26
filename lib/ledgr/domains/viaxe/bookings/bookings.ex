defmodule Ledgr.Domains.Viaxe.Bookings do
  @moduledoc """
  Context module for managing travel bookings.
  """

  import Ecto.Query
  alias Ledgr.Repo
  alias Ledgr.Domains.Viaxe.Bookings.{Booking, BookingItem, BookingPassenger, BookingPayment}
  alias Ledgr.Domains.Viaxe.Customers.Customer

  # ── Bookings ───────────────────────────────────────────────

  def list_bookings(opts \\ []) do
    status = Keyword.get(opts, :status)

    Booking
    |> maybe_filter_status(status)
    |> order_by(desc: :booking_date)
    |> preload([:customer, :trip, :booking_items, :booking_payments])
    |> Repo.all()
    |> Enum.map(&put_customer_name/1)
  end

  def get_booking!(id) do
    Booking
    |> preload([
      :customer,
      :trip,
      booking_items: [:service, :supplier],
      booking_payments: [:cash_account, :partner],
      booking_passengers: [:customer]
    ])
    |> Repo.get!(id)
    |> put_customer_name()
  end

  def create_booking(attrs \\ %{}) do
    %Booking{}
    |> Booking.changeset(attrs)
    |> Repo.insert()
  end

  def update_booking(%Booking{} = booking, attrs) do
    booking
    |> Booking.changeset(attrs)
    |> Repo.update()
  end

  def delete_booking(%Booking{} = booking) do
    Repo.delete(booking)
  end

  def change_booking(%Booking{} = booking, attrs \\ %{}) do
    Booking.changeset(booking, attrs)
  end

  def update_booking_status(%Booking{} = booking, new_status) do
    booking
    |> Booking.changeset(%{status: new_status})
    |> Repo.update()
  end

  # ── Booking Passengers ─────────────────────────────────────

  def add_booking_passenger(booking_id, customer_id) do
    %BookingPassenger{}
    |> BookingPassenger.changeset(%{booking_id: booking_id, customer_id: customer_id})
    |> Repo.insert()
  end

  def remove_booking_passenger(booking_id, customer_id) do
    case Repo.get_by(BookingPassenger, booking_id: booking_id, customer_id: customer_id) do
      nil -> {:error, :not_found}
      bp -> Repo.delete(bp)
    end
  end

  # ── Booking Items ──────────────────────────────────────────

  def create_booking_item(attrs \\ %{}) do
    result =
      %BookingItem{}
      |> BookingItem.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, item} ->
        recalculate_booking_totals(item.booking_id)
        {:ok, item}

      error ->
        error
    end
  end

  def delete_booking_item(%BookingItem{} = item) do
    booking_id = item.booking_id
    result = Repo.delete(item)

    case result do
      {:ok, _} ->
        recalculate_booking_totals(booking_id)
        result

      error ->
        error
    end
  end

  def change_booking_item(%BookingItem{} = item, attrs \\ %{}) do
    BookingItem.changeset(item, attrs)
  end

  # ── Booking Payments ───────────────────────────────────────

  def create_booking_payment(attrs \\ %{}) do
    %BookingPayment{}
    |> BookingPayment.changeset(attrs)
    |> Repo.insert()
  end

  def total_paid(booking_id) do
    BookingPayment
    |> where(booking_id: ^booking_id)
    |> select([p], sum(p.amount_cents))
    |> Repo.one() || 0
  end

  def payment_summary(booking) do
    paid = total_paid(booking.id)
    total = booking.total_price_cents

    %{
      total_cents: total,
      paid_cents: paid,
      remaining_cents: max(total - paid, 0),
      fully_paid?: paid >= total and total > 0,
      partially_paid?: paid > 0 and paid < total
    }
  end

  # ── Stats ──────────────────────────────────────────────────

  def count_by_status do
    Booking
    |> group_by(:status)
    |> select([b], {b.status, count(b.id)})
    |> Repo.all()
    |> Map.new()
  end

  # ── Private helpers ────────────────────────────────────────

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, ""), do: query
  defp maybe_filter_status(query, status), do: where(query, status: ^status)

  defp put_customer_name(%Booking{customer: %Customer{} = customer} = booking) do
    %{booking | customer_name: Customer.full_name(customer)}
  end

  defp put_customer_name(booking), do: %{booking | customer_name: "Unknown"}

  defp recalculate_booking_totals(booking_id) do
    booking = Repo.get!(Booking, booking_id)
    items = BookingItem |> where(booking_id: ^booking_id) |> Repo.all()

    total_cost = Enum.reduce(items, 0, fn i, acc -> acc + i.cost_cents * i.quantity end)
    total_price = Enum.reduce(items, 0, fn i, acc -> acc + i.price_cents * i.quantity end)

    commission =
      cond do
        booking.commission_type == "fixed" && booking.commission_value ->
          booking.commission_value

        booking.commission_type == "percentage" && booking.commission_value && total_price > 0 ->
          div(total_price * booking.commission_value, 10_000)

        true ->
          total_price - total_cost
      end

    Booking
    |> where(id: ^booking_id)
    |> Repo.update_all(
      set: [
        total_cost_cents: total_cost,
        total_price_cents: total_price,
        commission_cents: max(commission, 0)
      ]
    )
  end
end
