defmodule Ledgr.Repo.Migrations.AddSamplesGiftsAccount do
  use Ecto.Migration

  def up do
    execute """
    INSERT INTO accounts (code, name, type, normal_balance, inserted_at, updated_at)
    VALUES ('6070', 'Samples & Gifts', 'expense', 'debit', NOW(), NOW())
    ON CONFLICT (code) DO NOTHING
    """
  end

  def down do
    execute "DELETE FROM accounts WHERE code = '6070'"
  end
end
