defmodule Ledgr.Repo.Migrations.AddSplitPaymentFieldsToOrderPayments do
  use Ecto.Migration

  def change do
    alter table(:order_payments) do
      # Split payment fields
      add :customer_amount_cents, :integer
      add :partner_amount_cents, :integer
      add :partner_id, references(:partners, on_delete: :nilify_all)
      add :partner_payable_account_id, references(:accounts, on_delete: :nilify_all)
    end

    create index(:order_payments, [:partner_id])
    create index(:order_payments, [:partner_payable_account_id])
  end
end
