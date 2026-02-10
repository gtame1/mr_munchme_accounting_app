defmodule Ledgr.Partners.CapitalContribution do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Partners.Partner
  alias Ledgr.Accounting.Account

  schema "capital_contributions" do
    field :date, :date
    field :amount_cents, :integer
    field :note, :string

    # "in"  -> owner puts money in
    # "out" -> owner takes money out
    field :direction, :string, default: "in"

    belongs_to :partner, Partner

    # NEW: where the cash actually lands / leaves
    belongs_to :cash_account, Account

    timestamps()
  end

  @directions ~w(in out)

  def changeset(contribution, attrs) do
    contribution
    |> cast(attrs, [:partner_id, :date, :amount_cents, :note, :direction, :cash_account_id])
    |> validate_required([:partner_id, :date, :amount_cents, :direction, :cash_account_id])
    |> validate_inclusion(:direction, @directions)
    |> validate_number(:amount_cents, greater_than: 0)
    |> foreign_key_constraint(:partner_id)
    |> foreign_key_constraint(:cash_account_id)
  end
end
