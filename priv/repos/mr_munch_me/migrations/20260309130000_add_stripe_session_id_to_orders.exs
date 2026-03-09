defmodule Ledgr.Repos.MrMunchMe.Migrations.AddStripeSessionIdToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :stripe_checkout_session_id, :string
    end

    create index(:orders, [:stripe_checkout_session_id])
  end
end
