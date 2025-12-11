defmodule MrMunchMeAccountingApp.Inventory.RecipeLine do
  use Ecto.Schema
  import Ecto.Changeset

  alias MrMunchMeAccountingApp.Inventory.Recipe

  schema "recipe_lines" do
    belongs_to :recipe, Recipe
    field :ingredient_code, :string
    field :quantity, :decimal
    field :comment, :string

    timestamps()
  end

  def changeset(recipe_line, attrs) do
    recipe_line
    |> cast(attrs, [:ingredient_code, :quantity, :comment])
    |> validate_required([:ingredient_code, :quantity])
    |> validate_number(:quantity, greater_than: 0)
  end
end
