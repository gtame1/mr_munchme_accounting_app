defmodule Ledgr.Repos.VolumeStudio.Migrations.AddPlanTypeAndDurationDaysToSubscriptionPlans do
  use Ecto.Migration

  def change do
    alter table(:subscription_plans) do
      add :plan_type, :string, null: false, default: "membership"
      add :duration_days, :integer
    end
  end
end
