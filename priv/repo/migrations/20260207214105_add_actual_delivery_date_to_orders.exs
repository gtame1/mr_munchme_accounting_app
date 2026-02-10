defmodule Ledgr.Repo.Migrations.AddActualDeliveryDateToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :actual_delivery_date, :date
    end

    # Backfill: for already-delivered orders, set actual_delivery_date = delivery_date
    execute(
      "UPDATE orders SET actual_delivery_date = delivery_date WHERE status = 'delivered'",
      "UPDATE orders SET actual_delivery_date = NULL"
    )
  end
end
