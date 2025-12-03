defmodule MrMunchMeAccountingApp.Inventory.Recipe do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias MrMunchMeAccountingApp.Orders.Product
  alias MrMunchMeAccountingApp.Inventory.RecipeLine
  alias MrMunchMeAccountingApp.Repo

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
    |> validate_unique_recipe()
    |> cast_assoc(:recipe_lines, with: &RecipeLine.changeset/2)
    |> unique_constraint([:product_id, :effective_date], name: :recipes_product_id_effective_date_index)
  end

  defp validate_unique_recipe(changeset) do
    product_id = get_field(changeset, :product_id)
    effective_date = get_field(changeset, :effective_date)

    if product_id && effective_date do
      query =
        from r in __MODULE__,
          where: r.product_id == ^product_id and r.effective_date == ^effective_date

      # Exclude the current recipe if we're updating
      query =
        case changeset.data do
          %{id: id} when not is_nil(id) ->
            from r in query, where: r.id != ^id

          _ ->
            query
        end

      if Repo.exists?(query) do
        add_error(
          changeset,
          :effective_date,
          "A recipe for this product already exists with this effective date. Please choose a different date."
        )
      else
        changeset
      end
    else
      changeset
    end
  end
end
