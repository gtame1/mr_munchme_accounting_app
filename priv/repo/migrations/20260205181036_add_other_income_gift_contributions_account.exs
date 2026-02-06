defmodule MrMunchMeAccountingApp.Repo.Migrations.AddOtherIncomeGiftContributionsAccount do
  use Ecto.Migration

  def up do
    execute """
    INSERT INTO accounts (code, name, type, normal_balance, inserted_at, updated_at)
    VALUES ('4100', 'Other Income (Gift Contributions)', 'revenue', 'credit', NOW(), NOW())
    ON CONFLICT (code) DO NOTHING
    """
  end

  def down do
    execute "DELETE FROM accounts WHERE code = '4100'"
  end
end
