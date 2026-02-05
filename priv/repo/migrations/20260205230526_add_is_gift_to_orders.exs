defmodule MrMunchMeAccountingApp.Repo.Migrations.AddIsGiftToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :is_gift, :boolean, default: false, null: false
    end
  end
end
