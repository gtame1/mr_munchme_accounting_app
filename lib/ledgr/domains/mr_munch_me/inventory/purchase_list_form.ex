defmodule Ledgr.Domains.MrMunchMe.Inventory.PurchaseListForm do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Domains.MrMunchMe.Inventory.PurchaseItemForm

  @primary_key false
  embedded_schema do
    field :location_code, :string
    field :paid_from_account_id, :string
    field :purchase_date, :date
    field :notes, :string

    embeds_many :items, PurchaseItemForm, on_replace: :delete
  end

  def changeset(form, attrs) do
    form
    |> cast(attrs, [:location_code, :paid_from_account_id, :purchase_date, :notes])
    |> validate_required([:location_code, :paid_from_account_id, :purchase_date])
    |> cast_embed(:items, with: &PurchaseItemForm.changeset/2, required: true)
    |> validate_length(:items, min: 1, message: "must have at least one item")
  end
end
