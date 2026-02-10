defmodule Ledgr.Accounting.JournalLine do
  use Ecto.Schema
  import Ecto.Changeset

  schema "journal_lines" do
    field :description, :string
    field :debit_cents, :integer, default: 0
    field :credit_cents, :integer, default: 0

    belongs_to :journal_entry, Ledgr.Accounting.JournalEntry
    belongs_to :account, Ledgr.Accounting.Account

    timestamps()
  end

  def changeset(line, attrs) do
    line
    |> cast(attrs, [:description, :debit_cents, :credit_cents, :account_id])
    |> validate_required([:account_id])
    |> validate_number(:debit_cents, greater_than_or_equal_to: 0)
    |> validate_number(:credit_cents, greater_than_or_equal_to: 0)
    |> validate_non_zero()
  end

  defp validate_non_zero(changeset) do
    debit = get_field(changeset, :debit_cents) || 0
    credit = get_field(changeset, :credit_cents) || 0

    if debit == 0 and credit == 0 do
      add_error(changeset, :base, "line must have a debit or a credit")
    else
      changeset
    end
  end
end
