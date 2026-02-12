defmodule Ledgr.Repo.Migrations.AddIvaCentsToExpenses do
  use Ecto.Migration

  def change do
    alter table(:expenses) do
      add :iva_cents, :integer, default: 0
    end
  end
end
