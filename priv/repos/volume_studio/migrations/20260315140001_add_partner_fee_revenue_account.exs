defmodule Ledgr.Repos.VolumeStudio.Migrations.AddPartnerFeeRevenueAccount do
  use Ecto.Migration

  def up do
    execute """
    INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at)
    VALUES ('4040', 'Partner Fee Revenue', 'revenue', 'credit', false, false, NOW(), NOW())
    ON CONFLICT (code) DO NOTHING
    """
  end

  def down do
    execute "DELETE FROM accounts WHERE code = '4040'"
  end
end
