defmodule Ledgr.Core.Partners.Partner do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Core.Partners.CapitalContribution

  schema "partners" do
    field :name, :string
    field :email, :string
    field :phone, :string
    # Default partner fee rate in basis points (e.g. 2000 = 20%).
    # Used as a UI convenience default when creating bookings; actual rate
    # is stored per-booking in bookings.partner_fee_rate.
    field :default_fee_rate, :integer, default: 0

    has_many :capital_contributions, CapitalContribution

    timestamps()
  end

  def changeset(partner, attrs) do
    partner
    |> cast(attrs, [:name, :email, :phone, :default_fee_rate])
    |> validate_required([:name])
    |> validate_format(:email, ~r/@/, message: "must be a valid email")
    |> unique_constraint(:email)
  end
end
