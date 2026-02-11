defmodule Ledgr.Repo.Migrations.AddCustomerPaidShippingToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :customer_paid_shipping, :boolean, default: false, null: false
    end
  end
end
