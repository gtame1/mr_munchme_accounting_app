defmodule Ledgr.Repos.MrMunchMe.Migrations.AddSpecialInstructionsToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :special_instructions, :string
    end
  end
end
