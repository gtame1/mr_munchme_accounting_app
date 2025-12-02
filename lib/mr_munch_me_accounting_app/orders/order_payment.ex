defmodule MrMunchMeAccountingApp.Orders.OrderPayment do
  use Ecto.Schema
  import Ecto.Changeset

  alias MrMunchMeAccountingApp.Orders.Order
  alias MrMunchMeAccountingApp.Accounting.Account

  schema "order_payments" do
    field :payment_date, :date
    field :amount_cents, :integer
    field :method, :string
    field :note, :string
    field :is_deposit, :boolean, default: false

    belongs_to :order, Order
    belongs_to :paid_to_account, Account

    timestamps()
  end

  @required ~w(order_id payment_date amount_cents paid_to_account_id)a
  @optional ~w(method note is_deposit)a

  def changeset(payment, attrs) do
    payment
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_number(:amount_cents, greater_than: 0)
    |> assoc_constraint(:order)
    |> assoc_constraint(:paid_to_account)
  end
end
