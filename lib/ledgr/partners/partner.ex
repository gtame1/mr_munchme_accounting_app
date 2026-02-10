defmodule Ledgr.Partners.Partner do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Partners.CapitalContribution

  schema "partners" do
    field :name, :string
    field :email, :string
    field :phone, :string

    has_many :capital_contributions, CapitalContribution

    timestamps()
  end

  def changeset(partner, attrs) do
    partner
    |> cast(attrs, [:name, :email, :phone])
    |> validate_required([:name])
    |> validate_format(:email, ~r/@/, message: "must be a valid email")
    |> unique_constraint(:email)
  end
end
