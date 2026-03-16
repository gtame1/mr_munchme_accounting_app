defmodule Ledgr.Repos.VolumeStudio.Migrations.RemovePaidCentsFromClassBookings do
  use Ecto.Migration

  def up do
    alter table(:class_bookings) do
      remove :paid_cents
    end
  end

  def down do
    alter table(:class_bookings) do
      add :paid_cents, :integer, default: 0, null: false
    end
  end
end
