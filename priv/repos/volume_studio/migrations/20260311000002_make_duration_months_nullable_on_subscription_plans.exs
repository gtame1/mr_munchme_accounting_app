defmodule Ledgr.Repos.VolumeStudio.Migrations.MakeDurationMonthsNullableOnSubscriptionPlans do
  use Ecto.Migration

  def change do
    alter table(:subscription_plans) do
      modify :duration_months, :integer, null: true, default: nil
    end
  end
end
