defmodule Ledgr.Repo.Migrations.AddCommentsToRecipeLines do
  use Ecto.Migration

  def change do
    alter table(:recipe_lines) do
      add :comment, :text
    end
  end
end
