defmodule Ledgr.Repos.VolumeStudio.Migrations.NullDurationMonthsForExtraPlans do
  use Ecto.Migration

  def up do
    execute("UPDATE subscription_plans SET duration_months = NULL WHERE plan_type = 'extra'")
  end

  def down do
    execute("UPDATE subscription_plans SET duration_months = 1 WHERE plan_type = 'extra' AND duration_months IS NULL")
  end
end
