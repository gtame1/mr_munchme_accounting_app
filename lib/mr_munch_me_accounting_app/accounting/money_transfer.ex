defmodule MrMunchMeAccountingApp.Accounting.MoneyTransfer do
  use Ecto.Schema
  import Ecto.Changeset

  alias MrMunchMeAccountingApp.Accounting.Account

  schema "money_transfers" do
    field :date, :date
    field :amount_cents, :integer
    field :note, :string

    belongs_to :from_account, Account
    belongs_to :to_account, Account

    timestamps()
  end

  def changeset(transfer, attrs) do
    transfer
    |> cast(attrs, [:from_account_id, :to_account_id, :date, :amount_cents, :note])
    |> validate_required([:from_account_id, :to_account_id, :date, :amount_cents])
    |> validate_number(:amount_cents, greater_than: 0)
  end
end
