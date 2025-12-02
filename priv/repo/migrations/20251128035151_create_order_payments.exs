defmodule MrMunchMeAccountingApp.Repo.Migrations.CreateOrderPayments do
  use Ecto.Migration

  def change do
    create table(:order_payments) do
      add :order_id, references(:orders, on_delete: :delete_all), null: false
      add :payment_date, :date, null: false
      add :amount_cents, :integer, null: false

      # where the money went (cash, bank, card payable, etc.)
      add :paid_to_account_id, references(:accounts, on_delete: :restrict), null: false

      add :method, :string
      add :note, :text

      # for future: mark advance payments
      add :is_deposit, :boolean, null: false, default: false

      timestamps()
    end

    create index(:order_payments, [:order_id])
    create index(:order_payments, [:payment_date])
  end
end
