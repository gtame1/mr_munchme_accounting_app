defmodule MrMunchMeAccountingApp.Inventory.MovementItemForm do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :ingredient_code, :string
    field :quantity, :integer
  end

  def changeset(form, attrs) do
    form
    |> cast(attrs, [:ingredient_code, :quantity])
    |> validate_required([:ingredient_code, :quantity])
    |> validate_number(:quantity, greater_than: 0)
  end
end
