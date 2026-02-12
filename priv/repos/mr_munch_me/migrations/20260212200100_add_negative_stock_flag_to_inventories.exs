defmodule Ledgr.Repo.Migrations.AddNegativeStockFlagToInventories do
  use Ecto.Migration

  def change do
    alter table(:inventories) do
      add :negative_stock, :boolean, default: false, null: false
    end
  end
end
