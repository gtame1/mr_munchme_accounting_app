defmodule Ledgr.Core.Accounting.Account do
  use Ecto.Schema
  import Ecto.Changeset

  schema "accounts" do
    field :code, :string
    field :name, :string
    field :type, :string
    field :normal_balance, :string
    field :is_cash, :boolean, default: false
    field :is_cogs, :boolean, default: false

    has_many :journal_lines, Ledgr.Core.Accounting.JournalLine

    timestamps()
  end

  @required_fields ~w(code name type normal_balance)a
  @types ~w(asset liability equity revenue expense)
  @normal_balances ~w(debit credit)

  def changeset(account, attrs) do
    account
    |> cast(attrs, [:code, :name, :type, :normal_balance, :is_cash, :is_cogs])
    |> validate_required(@required_fields)
    |> validate_inclusion(:type, @types)
    |> validate_inclusion(:normal_balance, @normal_balances)
    |> unique_constraint(:code)
  end
end
