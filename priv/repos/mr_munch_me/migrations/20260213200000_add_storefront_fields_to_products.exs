defmodule Ledgr.Repo.Migrations.AddStorefrontFieldsToProducts do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :description, :text
      add :image_url, :string
    end
  end
end
