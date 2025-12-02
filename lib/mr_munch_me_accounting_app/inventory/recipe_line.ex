defmodule MrMunchMeAccountingApp.Inventory.RecipeLine do
  use Ecto.Schema
  import Ecto.Changeset

  alias MrMunchMeAccountingApp.Inventory.Recipe

  schema "recipe_lines" do
    belongs_to :recipe, Recipe
    field :ingredient_code, :string
    field :quantity, :decimal

    timestamps()
  end

  def changeset(recipe_line, attrs) do
    recipe_line
    |> cast(attrs, [:recipe_id, :ingredient_code, :quantity])
    |> validate_required([:recipe_id, :ingredient_code, :quantity])
    |> validate_number(:quantity, greater_than: 0)
  end
end
