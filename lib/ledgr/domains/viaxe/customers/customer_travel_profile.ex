defmodule Ledgr.Domains.Viaxe.Customers.CustomerTravelProfile do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Domains.Viaxe.Customers.Customer

  schema "customer_travel_profiles" do
    belongs_to :customer, Customer

    field :dob, :date
    field :gender, :string             # male, female, other, prefer_not_to_say
    field :nationality, :string        # country code e.g. "MX", "US"
    field :home_address, :string
    field :tsa_precheck_number, :string
    field :seat_preference, :string    # window, aisle, middle, no_preference
    field :meal_preference, :string    # regular, vegetarian, vegan, halal, kosher, gluten_free
    field :medical_notes, :string      # allergies, vaccines, special needs
    field :emergency_contact_name, :string
    field :emergency_contact_phone, :string

    timestamps(type: :utc_datetime)
  end

  @optional_fields [
    :dob, :gender, :nationality, :home_address, :tsa_precheck_number,
    :seat_preference, :meal_preference, :medical_notes,
    :emergency_contact_name, :emergency_contact_phone
  ]

  def changeset(profile, attrs) do
    profile
    |> cast(attrs, [:customer_id | @optional_fields])
    |> validate_required([:customer_id])
    |> validate_inclusion(:gender, ~w(male female other prefer_not_to_say))
    |> validate_inclusion(:seat_preference, ~w(window aisle middle no_preference))
    |> validate_inclusion(:meal_preference, ~w(regular vegetarian vegan halal kosher gluten_free))
    |> foreign_key_constraint(:customer_id)
    |> unique_constraint(:customer_id)
  end
end
