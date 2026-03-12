defmodule Ledgr.Domains.VolumeStudio.SubscriptionPlans.SubscriptionPlan do
  use Ecto.Schema
  import Ecto.Changeset

  schema "subscription_plans" do
    field :name, :string
    field :description, :string
    field :price_cents, :integer
    field :plan_type, :string, default: "membership"  # package | membership | promo | extra
    field :duration_months, :integer, default: 1
    field :duration_days, :integer  # nil = not used; overrides duration_months for packages/promos
    field :class_limit, :integer    # nil = unlimited
    field :active, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  @required_fields [:name, :price_cents]
  @optional_fields [:description, :plan_type, :duration_months, :duration_days, :class_limit, :active]

  def changeset(plan, attrs) do
    plan
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:price_cents, greater_than: 0)
    |> validate_number(:duration_months, greater_than: 0)
    |> validate_number(:duration_days, greater_than: 0)
    |> validate_number(:class_limit, greater_than_or_equal_to: 0)
    |> validate_inclusion(:plan_type, ~w(package membership promo extra))
  end
end
