defmodule Ledgr.Domains.Viaxe.TravelDocuments.LoyaltyProgram do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Domains.Viaxe.Customers.Customer

  schema "loyalty_programs" do
    belongs_to :customer, Customer

    field :program_name, :string      # e.g. "AAdvantage", "Marriott Bonvoy"
    field :program_type, :string      # airline, hotel, car_rental, other
    field :member_number, :string
    field :tier, :string              # Gold, Platinum, Elite, etc.
    field :notes, :string

    timestamps(type: :utc_datetime)
  end

  @required_fields [:customer_id, :program_name, :member_number]
  @optional_fields [:program_type, :tier, :notes]

  def changeset(program, attrs) do
    program
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:program_type, ~w(airline hotel car_rental other))
    |> foreign_key_constraint(:customer_id)
  end
end
