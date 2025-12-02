defmodule MrMunchMeAccountingApp.Repo.Migrations.CreatePartners do
  use Ecto.Migration

  def change do
    create table(:partners) do
      add :name, :string, null: false
      add :email, :string
      add :phone, :string

      timestamps()
    end

    create unique_index(:partners, [:email])

    create table(:capital_contributions) do
      add :partner_id, references(:partners, on_delete: :delete_all), null: false
      add :date, :date, null: false
      add :amount_cents, :integer, null: false
      add :note, :text

      timestamps()
    end

    create index(:capital_contributions, [:partner_id])
    create index(:capital_contributions, [:date])
  end
end
