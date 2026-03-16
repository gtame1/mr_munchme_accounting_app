defmodule Ledgr.Repos.VolumeStudio.Migrations.AddCompletedStatusToSubscriptions do
  use Ecto.Migration

  def up do
    drop constraint(:subscriptions, :valid_status)

    create constraint(:subscriptions, :valid_status,
      check: "status IN ('active','paused','cancelled','expired','completed')"
    )
  end

  def down do
    drop constraint(:subscriptions, :valid_status)

    create constraint(:subscriptions, :valid_status,
      check: "status IN ('active','paused','cancelled','expired')"
    )
  end
end
