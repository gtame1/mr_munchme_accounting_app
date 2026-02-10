defmodule Ledgr.Repo.Migrations.AddQuantityToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :quantity, :integer, default: 1, null: false
    end
  end
end
