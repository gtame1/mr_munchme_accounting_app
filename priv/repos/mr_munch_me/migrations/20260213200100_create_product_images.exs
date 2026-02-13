defmodule Ledgr.Repos.MrMunchMe.Migrations.CreateProductImages do
  use Ecto.Migration

  def change do
    create table(:product_images) do
      add :product_id, references(:products, on_delete: :delete_all), null: false
      add :image_url, :string, null: false
      add :position, :integer, default: 0

      timestamps()
    end

    create index(:product_images, [:product_id])
  end
end
