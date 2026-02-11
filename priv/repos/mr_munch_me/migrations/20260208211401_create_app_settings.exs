defmodule Ledgr.Repo.Migrations.CreateAppSettings do
  use Ecto.Migration

  def change do
    create table(:app_settings) do
      add :key, :string, null: false
      add :value, :string

      timestamps()
    end

    create unique_index(:app_settings, [:key])
  end
end
