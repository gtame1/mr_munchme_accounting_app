defmodule Ledgr.Repos.MrMunchMe.Migrations.AddDeletedAtToCustomers do
  use Ecto.Migration

  def change do
    alter table(:customers) do
      add :deleted_at, :utc_datetime, null: true
    end

    create index(:customers, [:deleted_at])
  end
end
