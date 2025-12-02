defmodule MrMunchMeAccountingApp.Inventory.Recipe do
  use Ecto.Schema
  import Ecto.Changeset

  alias MrMunchMeAccountingApp.Orders.Product
  alias MrMunchMeAccountingApp.Inventory.RecipeLine

  schema "recipes" do
    belongs_to :product, Product
    field :effective_date, :date
    field :name, :string
    field :description, :string

    has_many :recipe_lines, RecipeLine, on_replace: :delete

    timestamps()
  end

  def changeset(recipe, attrs) do
    recipe
    |> cast(attrs, [:product_id, :effective_date, :name, :description])
    |> validate_required([:product_id, :effective_date])
    |> cast_assoc(:recipe_lines, with: &RecipeLine.changeset/2)
    |> unique_constraint([:product_id, :effective_date], name: :recipes_product_id_effective_date_index)
  end
end
