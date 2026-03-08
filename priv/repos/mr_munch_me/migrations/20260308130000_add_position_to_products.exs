defmodule Ledgr.Repos.MrMunchMe.Migrations.AddPositionToProducts do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :position, :integer, default: 0, null: false
    end

    create index(:products, [:position])

    # Backfill: assign sequential positions (0, 1, 2...) ordered by name
    execute(
      """
      WITH ranked AS (
        SELECT id, (ROW_NUMBER() OVER (ORDER BY name ASC) - 1) AS pos
        FROM products
      )
      UPDATE products SET position = ranked.pos
      FROM ranked
      WHERE products.id = ranked.id
      """,
      "SELECT 1"
    )
  end
end
