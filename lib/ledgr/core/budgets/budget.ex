defmodule Ledgr.Core.Budgets.Budget do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Core.Accounting.Account

  schema "budgets" do
    field :year, :integer
    field :month, :integer
    field :amount_cents, :integer, default: 0

    belongs_to :account, Account

    timestamps()
  end

  @required_fields ~w(year month amount_cents account_id)a

  def changeset(budget, attrs) do
    budget
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> validate_number(:year, greater_than: 2020, less_than: 2100)
    |> validate_number(:month, greater_than_or_equal_to: 1, less_than_or_equal_to: 12)
    |> validate_number(:amount_cents, greater_than_or_equal_to: 0)
    |> assoc_constraint(:account)
    |> unique_constraint([:account_id, :year, :month])
  end
end
