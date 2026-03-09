defmodule Ledgr.Repos.MrMunchMe.Migrations.AddStripeFeesAccount do
  use Ecto.Migration

  def up do
    execute """
    INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at)
    VALUES ('6035', 'Payment Processing Fees', 'expense', 'debit', false, false, NOW(), NOW())
    ON CONFLICT (code) DO NOTHING
    """
  end

  def down do
    execute "DELETE FROM accounts WHERE code = '6035'"
  end
end
