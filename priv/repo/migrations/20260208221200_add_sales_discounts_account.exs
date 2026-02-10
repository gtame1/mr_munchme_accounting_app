defmodule MrMunchMeAccountingApp.Repo.Migrations.AddSalesDiscountsAccount do
  use Ecto.Migration

  def up do
    # Insert Sales Discounts contra-revenue account if it doesn't already exist
    execute """
    INSERT INTO accounts (code, name, type, normal_balance, inserted_at, updated_at)
    SELECT '4010', 'Sales Discounts', 'revenue', 'debit', NOW(), NOW()
    WHERE NOT EXISTS (SELECT 1 FROM accounts WHERE code = '4010')
    """
  end

  def down do
    execute "DELETE FROM accounts WHERE code = '4010'"
  end
end
