defmodule MrMunchMeAccountingApp.Repo.Migrations.CreateMoneyTransfers do
  use Ecto.Migration

  def change do
    create table(:money_transfers) do
      add :date, :date, null: false
      add :amount_cents, :integer, null: false
      add :note, :string

      add :from_account_id,
          references(:accounts, on_delete: :restrict),
          null: false

      add :to_account_id,
          references(:accounts, on_delete: :restrict),
          null: false

      timestamps()
    end

    create index(:money_transfers, [:date])
    create index(:money_transfers, [:from_account_id])
    create index(:money_transfers, [:to_account_id])
  end
end
