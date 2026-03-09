defmodule Ledgr.Repos.MrMunchMe.Migrations.CreatePendingCheckouts do
  use Ecto.Migration

  def change do
    create table(:pending_checkouts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :cart, :map, null: false
      add :customer_id, references(:customers, on_delete: :nilify_all)
      add :checkout_attrs, :map, null: false
      add :stripe_session_id, :string
      add :processed_at, :naive_datetime
      add :expires_at, :naive_datetime, null: false

      timestamps()
    end

    create index(:pending_checkouts, [:stripe_session_id])
    create index(:pending_checkouts, [:expires_at])
  end
end
