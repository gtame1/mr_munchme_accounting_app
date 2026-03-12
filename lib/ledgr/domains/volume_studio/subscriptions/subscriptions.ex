defmodule Ledgr.Domains.VolumeStudio.Subscriptions do
  @moduledoc """
  Context module for managing Volume Studio subscriptions.
  """

  import Ecto.Query

  alias Ledgr.Repo
  alias Ledgr.Domains.VolumeStudio.Subscriptions.Subscription
  alias Ledgr.Domains.VolumeStudio.Accounting.VolumeStudioAccounting

  @doc """
  Returns a list of subscriptions.

  Options:
    - `:status` — filter by status string, e.g. "active"
    - `:customer_id` — filter by customer
  """
  def list_subscriptions(opts \\ []) do
    status = Keyword.get(opts, :status)
    customer_id = Keyword.get(opts, :customer_id)

    Subscription
    |> maybe_filter_status(status)
    |> maybe_filter_customer(customer_id)
    |> order_by(desc: :inserted_at)
    |> preload([:customer, :subscription_plan])
    |> Repo.all()
  end

  @doc "Gets a single subscription with customer and plan preloaded. Raises if not found."
  def get_subscription!(id) do
    Subscription
    |> preload([:customer, :subscription_plan])
    |> Repo.get!(id)
  end

  @doc "Returns a changeset for the given subscription and attrs."
  def change_subscription(%Subscription{} = sub, attrs \\ %{}) do
    Subscription.changeset(sub, attrs)
  end

  @doc "Creates a subscription. No journal entry on creation — payment is recorded separately."
  def create_subscription(attrs \\ %{}) do
    %Subscription{}
    |> Subscription.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a subscription."
  def update_subscription(%Subscription{} = sub, attrs) do
    sub
    |> Subscription.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Records a subscription payment for the given amount.

  In a transaction:
    1. Adds amount_cents to deferred_revenue_cents on the subscription
    2. Creates journal entry: DR Cash / CR Deferred Sub Revenue

  Options:
    - `:payment_date` — defaults to today
    - `:method`       — payment method string (e.g. "cash", "card")
    - `:note`         — optional note for the journal entry line

  The subscription must have subscription_plan preloaded.
  """
  def record_payment(sub, amount_cents, opts \\ [])

  def record_payment(%Subscription{subscription_plan: plan} = sub, amount_cents, opts)
      when not is_nil(plan) and is_integer(amount_cents) and amount_cents > 0 do
    Repo.transaction(fn ->
      updated =
        sub
        |> Subscription.changeset(%{
          deferred_revenue_cents: sub.deferred_revenue_cents + amount_cents
        })
        |> Repo.update!()

      VolumeStudioAccounting.record_subscription_payment(sub, amount_cents, opts)

      updated
    end)
  end

  def record_payment(%Subscription{} = sub, amount_cents, opts) do
    # Plan not preloaded — reload and retry
    sub
    |> Repo.preload(:subscription_plan)
    |> record_payment(amount_cents, opts)
  end

  @doc """
  Recognizes a portion of deferred subscription revenue.

  In a transaction:
    1. Moves amount_cents from deferred_revenue_cents → recognized_revenue_cents
    2. Creates journal entry: DR Deferred Sub Revenue / CR Subscription Revenue
  """
  def recognize_revenue(%Subscription{} = sub, amount_cents) when amount_cents > 0 do
    available = sub.deferred_revenue_cents
    to_recognize = min(amount_cents, available)

    if to_recognize <= 0 do
      {:error, :no_deferred_revenue}
    else
      Repo.transaction(fn ->
        updated =
          sub
          |> Subscription.changeset(%{
            deferred_revenue_cents: sub.deferred_revenue_cents - to_recognize,
            recognized_revenue_cents: sub.recognized_revenue_cents + to_recognize
          })
          |> Repo.update!()

        VolumeStudioAccounting.recognize_subscription_revenue(sub, to_recognize)

        updated
      end)
    end
  end

  @doc "Cancels a subscription by updating its status and setting ends_on to today."
  def cancel(%Subscription{} = sub) do
    sub
    |> Subscription.changeset(%{
      status: "cancelled",
      ends_on: Date.utc_today()
    })
    |> Repo.update()
  end

  @doc """
  Returns a payment summary map for a subscription.

  Keys: :deferred, :recognized, :total_paid, :remaining, :outstanding_cents
  """
  def payment_summary(%Subscription{subscription_plan: plan} = sub) when not is_nil(plan) do
    total_paid = Subscription.total_paid_cents(sub)

    %{
      deferred:          sub.deferred_revenue_cents,
      recognized:        sub.recognized_revenue_cents,
      total_paid:        total_paid,
      remaining:         Subscription.remaining_deferred(sub),
      outstanding_cents: max(plan.price_cents - total_paid, 0)
    }
  end

  def payment_summary(%Subscription{} = sub) do
    sub
    |> Repo.preload(:subscription_plan)
    |> payment_summary()
  end

  # ── Private helpers ──────────────────────────────────────────────────

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, status: ^status)

  defp maybe_filter_customer(query, nil), do: query
  defp maybe_filter_customer(query, id), do: where(query, customer_id: ^id)
end
