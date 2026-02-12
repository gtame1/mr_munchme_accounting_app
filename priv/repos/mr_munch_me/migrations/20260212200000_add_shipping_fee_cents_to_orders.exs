defmodule Ledgr.Repo.Migrations.AddShippingFeeCentsToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :shipping_fee_cents, :integer
    end
  end
end
