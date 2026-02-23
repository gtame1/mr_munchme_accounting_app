defmodule Ledgr.Repos.MrMunchMe.Migrations.AddPayeeToExpensesAndJournalEntries do
  use Ecto.Migration

  def change do
    alter table(:expenses) do
      add :payee, :string
    end

    alter table(:journal_entries) do
      add :payee, :string
    end
  end
end
