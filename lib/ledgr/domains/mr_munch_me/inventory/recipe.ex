defmodule Ledgr.Domains.MrMunchMe.Inventory.Recipe do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Ledgr.Domains.MrMunchMe.Orders.ProductVariant
  alias Ledgr.Domains.MrMunchMe.Inventory.RecipeLine
  alias Ledgr.Repo

  schema "recipes" do
    belongs_to :variant, ProductVariant, foreign_key: :variant_id
    field :effective_date, :date
    field :name, :string
    field :description, :string

    has_many :recipe_lines, RecipeLine, on_replace: :delete

    timestamps()
  end

  def changeset(recipe, attrs) do
    recipe
    |> cast(attrs, [:variant_id, :effective_date, :name, :description])
    |> validate_required([:variant_id, :effective_date])
    |> validate_unique_recipe()
    |> cast_assoc(:recipe_lines, with: &RecipeLine.changeset/2)
    |> assoc_constraint(:variant)
  end

  defp validate_unique_recipe(changeset) do
    variant_id = get_field(changeset, :variant_id)
    effective_date = get_field(changeset, :effective_date)

    if variant_id && effective_date do
      query =
        from r in __MODULE__,
          where: r.variant_id == ^variant_id and r.effective_date == ^effective_date

      query = exclude_current(query, changeset)

      if Repo.exists?(query) do
        add_error(
          changeset,
          :effective_date,
          "A recipe for this variant already exists with this effective date. Please choose a different date."
        )
      else
        changeset
      end
    else
      changeset
    end
  end

  defp exclude_current(query, changeset) do
    case changeset.data do
      %{id: id} when not is_nil(id) -> from r in query, where: r.id != ^id
      _ -> query
    end
  end
end
