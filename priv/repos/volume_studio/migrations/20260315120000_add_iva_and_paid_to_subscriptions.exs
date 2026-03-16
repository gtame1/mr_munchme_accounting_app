defmodule Ledgr.VolumeStudioRepo.Migrations.AddIvaAndPaidToSubscriptions do
  use Ecto.Migration

  def up do
    alter table(:subscriptions) do
      add :iva_cents,  :integer, default: 0, null: false
      add :paid_cents, :integer, default: 0, null: false
    end

    # Backfill paid_cents from existing subscriptions.
    # Old subscriptions had no IVA, so all cash received = deferred + recognized.
    execute "UPDATE subscriptions SET paid_cents = deferred_revenue_cents + recognized_revenue_cents"
  end

  def down do
    alter table(:subscriptions) do
      remove :iva_cents
      remove :paid_cents
    end
  end
end
