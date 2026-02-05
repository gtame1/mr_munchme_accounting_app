defmodule MrMunchMeAccountingApp.Repo.Migrations.AddDiscountsToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :discount_type, :string  # "flat" or "percentage", nil means no discount
      add :discount_value, :decimal  # peso amount or percentage value
    end
  end
end
