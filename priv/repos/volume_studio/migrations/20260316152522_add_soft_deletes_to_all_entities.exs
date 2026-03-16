defmodule Ledgr.Repos.VolumeStudio.Migrations.AddSoftDeletesToAllEntities do
  use Ecto.Migration

  @tables ~w(
    customers
    subscription_plans
    subscriptions
    class_sessions
    class_bookings
    instructors
    spaces
    consultations
    space_rentals
  )a

  def up do
    for table <- @tables do
      alter table(table) do
        add :deleted_at, :utc_datetime, null: true
      end

      create index(table, [:deleted_at])
    end
  end

  def down do
    for table <- @tables do
      drop index(table, [:deleted_at])

      alter table(table) do
        remove :deleted_at
      end
    end
  end
end
