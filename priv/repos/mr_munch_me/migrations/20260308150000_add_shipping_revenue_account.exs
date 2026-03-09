defmodule Ledgr.Repos.MrMunchMe.Migrations.AddShippingRevenueAccount do
  use Ecto.Migration

  def up do
    execute """
    INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at)
    VALUES ('4020', 'Shipping Revenue', 'revenue', 'credit', false, false, NOW(), NOW())
    ON CONFLICT (code) DO NOTHING
    """
  end

  def down do
    execute "DELETE FROM accounts WHERE code = '4020'"
  end
end
