defmodule MrMunchMeAccountingApp.Repo.Migrations.AddUniqueIndexToCustomerPhone do
  use Ecto.Migration

  def change do
    create unique_index(:customers, [:phone])
  end
end
