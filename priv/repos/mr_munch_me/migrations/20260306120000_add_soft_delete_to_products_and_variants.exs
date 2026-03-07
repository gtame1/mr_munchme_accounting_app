defmodule Ledgr.Repos.MrMunchMe.Migrations.AddSoftDeleteToProductsAndVariants do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :deleted_at, :utc_datetime
    end

    alter table(:product_variants) do
      add :deleted_at, :utc_datetime
    end

    create index(:products, [:deleted_at])
    create index(:product_variants, [:deleted_at])
  end
end
