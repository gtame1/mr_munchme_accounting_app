defmodule Ledgr.Repo.Migrations.AddDeliveryAddressToCustomers do
  use Ecto.Migration

  def change do
    alter table(:customers) do
      add :delivery_address, :text
    end
  end
end
