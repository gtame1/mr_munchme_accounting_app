defmodule MrMunchMeAccountingApp.Repo.Migrations.AddPrepLocationToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :prep_location_id, references(:inventory_locations, on_delete: :restrict)
    end

    create index(:orders, [:prep_location_id])
  end
end
