defmodule Ledgr.Repos.MrMunchMe.Migrations.FinalizeVariants do
  use Ecto.Migration

  def up do
    # Make variant_id mandatory on orders and recipes
    execute "ALTER TABLE orders ALTER COLUMN variant_id SET NOT NULL"
    execute "ALTER TABLE recipes ALTER COLUMN variant_id SET NOT NULL"

    # Drop the product-keyed unique index on recipes (variant index remains)
    drop_if_exists index(:recipes, [:product_id, :effective_date],
                         name: :recipes_product_id_effective_date_index)

    # Remove product_id from orders and recipes
    alter table(:orders) do
      remove :product_id
    end

    alter table(:recipes) do
      remove :product_id
    end

    # Remove sku and price_cents from products (now on product_variants)
    alter table(:products) do
      remove :sku
      remove :price_cents
    end
  end

  def down do
    alter table(:products) do
      add :sku, :string
      add :price_cents, :integer
    end

    alter table(:recipes) do
      add :product_id, references(:products, on_delete: :restrict)
    end

    alter table(:orders) do
      add :product_id, references(:products, on_delete: :restrict)
    end

    create index(:recipes, [:product_id, :effective_date],
                 name: :recipes_product_id_effective_date_index)

    execute "ALTER TABLE orders ALTER COLUMN variant_id DROP NOT NULL"
    execute "ALTER TABLE recipes ALTER COLUMN variant_id DROP NOT NULL"
  end
end
