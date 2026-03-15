defmodule Ledgr.Repos.VolumeStudio.Migrations.CreateSpaceRentalPayments do
  use Ecto.Migration

  def change do
    create table(:space_rental_payments) do
      add :space_rental_id, references(:space_rentals, on_delete: :delete_all), null: false
      add :amount_cents,    :integer, null: false
      add :payment_date,    :date,    null: false
      add :method,          :string
      add :note,            :text

      timestamps(type: :utc_datetime)
    end

    create index(:space_rental_payments, [:space_rental_id])
  end
end
