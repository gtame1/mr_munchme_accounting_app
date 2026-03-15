defmodule Ledgr.Repos.VolumeStudio.Migrations.AddPaymentFieldsToSpaceRentals do
  use Ecto.Migration

  def change do
    alter table(:space_rentals) do
      add :discount_cents, :integer, default: 0, null: false
      add :paid_cents,     :integer, default: 0, null: false
    end
  end
end
