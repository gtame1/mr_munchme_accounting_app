defmodule Ledgr.Domains.VolumeStudio.ClassSessions.ClassBooking do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Core.Customers.Customer
  alias Ledgr.Domains.VolumeStudio.ClassSessions.ClassSession
  alias Ledgr.Domains.VolumeStudio.Subscriptions.Subscription

  schema "class_bookings" do
    belongs_to :customer, Customer
    belongs_to :class_session, ClassSession
    belongs_to :subscription, Subscription

    field :status, :string, default: "booked"

    timestamps(type: :utc_datetime)
  end

  @required_fields [:customer_id, :class_session_id]
  @optional_fields [:subscription_id, :status]

  @valid_statuses ~w(booked checked_in no_show cancelled)

  def changeset(booking, attrs) do
    booking
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, @valid_statuses)
    |> foreign_key_constraint(:customer_id)
    |> foreign_key_constraint(:class_session_id)
    |> foreign_key_constraint(:subscription_id, on_delete: :nilify_all)
    |> unique_constraint([:customer_id, :class_session_id])
  end
end
