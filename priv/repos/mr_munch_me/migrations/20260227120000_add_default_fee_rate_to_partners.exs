defmodule Ledgr.Repo.Migrations.AddDefaultFeeRateToPartners do
  use Ecto.Migration

  def change do
    alter table(:partners) do
      add :default_fee_rate, :integer, default: 0, null: false
    end
  end
end
