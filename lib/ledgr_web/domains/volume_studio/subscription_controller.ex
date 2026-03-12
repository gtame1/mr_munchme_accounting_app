defmodule LedgrWeb.Domains.VolumeStudio.SubscriptionController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.VolumeStudio.Subscriptions
  alias Ledgr.Domains.VolumeStudio.Subscriptions.Subscription
  alias Ledgr.Domains.VolumeStudio.SubscriptionPlans
  alias Ledgr.Domains.VolumeStudio.Accounting.VolumeStudioAccounting
  alias Ledgr.Core.Accounting
  alias Ledgr.Core.Customers
  alias Ledgr.Core.Customers.Customer

  def index(conn, params) do
    status = params["status"]
    subscriptions = Subscriptions.list_subscriptions(status: status)
    render(conn, :index, subscriptions: subscriptions, current_status: status)
  end

  def show(conn, %{"id" => id}) do
    subscription = Subscriptions.get_subscription!(id)
    summary = Subscriptions.payment_summary(subscription)
    render(conn, :show, subscription: subscription, summary: summary)
  end

  def new(conn, params) do
    mode = Map.get(params, "mode", "existing")
    changeset = Subscriptions.change_subscription(%Subscription{starts_on: Date.utc_today()})
    customer_changeset = Customers.change_customer(%Customer{})
    customers = customer_options()
    plans = SubscriptionPlans.list_active_subscription_plans()
    render(conn, :new,
      changeset: changeset,
      customer_changeset: customer_changeset,
      customers: customers,
      plans: plans,
      mode: mode,
      action: dp(conn, "/subscriptions")
    )
  end

  def create(conn, %{"subscription" => params}) do
    mode = Map.get(params, "mode", "existing")
    new_customer_params = Map.get(params, "new_customer", %{})
    sub_params = Map.drop(params, ["mode", "new_customer"])

    result =
      if mode == "new" do
        case Customers.create_customer(new_customer_params) do
          {:ok, customer} ->
            Subscriptions.create_subscription(Map.put(sub_params, "customer_id", customer.id))
          {:error, customer_changeset} ->
            {:error, :customer, customer_changeset}
        end
      else
        Subscriptions.create_subscription(sub_params)
      end

    case result do
      {:ok, sub} ->
        conn
        |> put_flash(:info, "Subscription created successfully.")
        |> redirect(to: dp(conn, "/subscriptions/#{sub.id}"))

      {:error, :customer, customer_changeset} ->
        customers = customer_options()
        plans = SubscriptionPlans.list_active_subscription_plans()
        render(conn, :new,
          changeset: Subscriptions.change_subscription(%Subscription{}),
          customer_changeset: customer_changeset,
          customers: customers,
          plans: plans,
          mode: "new",
          action: dp(conn, "/subscriptions")
        )

      {:error, %Ecto.Changeset{} = changeset} ->
        customers = customer_options()
        plans = SubscriptionPlans.list_active_subscription_plans()
        render(conn, :new,
          changeset: changeset,
          customer_changeset: Customers.change_customer(%Customer{}),
          customers: customers,
          plans: plans,
          mode: mode,
          action: dp(conn, "/subscriptions")
        )
    end
  end

  def edit(conn, %{"id" => id}) do
    subscription = Subscriptions.get_subscription!(id)
    changeset = Subscriptions.change_subscription(subscription)
    customers = customer_options()
    plans = SubscriptionPlans.list_active_subscription_plans()
    render(conn, :edit,
      subscription: subscription,
      changeset: changeset,
      customers: customers,
      plans: plans,
      action: dp(conn, "/subscriptions/#{id}")
    )
  end

  def update(conn, %{"id" => id, "subscription" => params}) do
    subscription = Subscriptions.get_subscription!(id)

    case Subscriptions.update_subscription(subscription, params) do
      {:ok, sub} ->
        conn
        |> put_flash(:info, "Subscription updated.")
        |> redirect(to: dp(conn, "/subscriptions/#{sub.id}"))

      {:error, %Ecto.Changeset{} = changeset} ->
        customers = customer_options()
        plans = SubscriptionPlans.list_active_subscription_plans()
        render(conn, :edit,
          subscription: subscription,
          changeset: changeset,
          customers: customers,
          plans: plans,
          action: dp(conn, "/subscriptions/#{id}")
        )
    end
  end

  def new_payment(conn, %{"id" => id}) do
    subscription      = Subscriptions.get_subscription!(id)
    summary           = Subscriptions.payment_summary(subscription)
    render(conn, :new_payment,
      subscription:      subscription,
      outstanding_cents: summary.outstanding_cents,
      change_accounts:   Accounting.cash_or_bank_account_options(),
      action:            dp(conn, "/subscriptions/#{id}/payment")
    )
  end

  def record_payment(conn, %{"id" => id, "payment" => payment_params}) do
    subscription       = Subscriptions.get_subscription!(id)
    summary            = Subscriptions.payment_summary(subscription)
    outstanding_before = summary.outstanding_cents
    amount_str         = Map.get(payment_params, "amount", "")
    method             = Map.get(payment_params, "method")
    note               = Map.get(payment_params, "note")
    date_str           = Map.get(payment_params, "payment_date", "")
    owed_change_choice = Map.get(payment_params, "owed_change_choice", "keep")

    with {amount_float, _} <- Float.parse(amount_str),
         amount_cents = round(amount_float * 100),
         true <- amount_cents > 0,
         {:ok, payment_date} <- Date.from_iso8601(date_str) do
      opts = [method: method, note: note, payment_date: payment_date]

      case Subscriptions.record_payment(subscription, amount_cents, opts) do
        {:ok, _} ->
          overpayment = max(0, amount_cents - outstanding_before)

          cond do
            owed_change_choice == "record" and overpayment > 0 ->
              fresh_sub = Subscriptions.get_subscription!(id)
              VolumeStudioAccounting.record_owed_change_ap(fresh_sub, overpayment,
                payment_date: payment_date
              )

            owed_change_choice == "staff_gave_change" ->
              change_given_str    = Map.get(payment_params, "change_given", "0")
              change_from_account = Map.get(payment_params, "change_from_account", "")

              case Float.parse(change_given_str) do
                {change_float, _} ->
                  change_given_cents = round(change_float * 100)

                  if change_given_cents > 0 and change_from_account != "" do
                    fresh_sub = Subscriptions.get_subscription!(id)
                    VolumeStudioAccounting.record_change_given(
                      fresh_sub,
                      change_given_cents,
                      change_from_account,
                      payment_date: payment_date
                    )
                  end

                :error ->
                  :ok
              end

            true ->
              :ok
          end

          conn
          |> put_flash(:info, "Payment of $#{amount_str} MXN recorded successfully.")
          |> redirect(to: dp(conn, "/subscriptions/#{id}"))

        {:error, reason} ->
          conn
          |> put_flash(:error, "Could not record payment: #{inspect(reason)}")
          |> redirect(to: dp(conn, "/subscriptions/#{id}/payment/new"))
      end
    else
      _ ->
        conn
        |> put_flash(:error, "Invalid amount or date. Please check the form.")
        |> redirect(to: dp(conn, "/subscriptions/#{id}/payment/new"))
    end
  end

  def cancel(conn, %{"id" => id}) do
    subscription = Subscriptions.get_subscription!(id)

    case Subscriptions.cancel(subscription) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Subscription cancelled.")
        |> redirect(to: dp(conn, "/subscriptions/#{id}"))

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Could not cancel subscription.")
        |> redirect(to: dp(conn, "/subscriptions/#{id}"))
    end
  end

  defp customer_options do
    Customers.list_customers()
    |> Enum.map(&{"#{&1.name} (#{&1.phone})", &1.id})
  end
end

defmodule LedgrWeb.Domains.VolumeStudio.SubscriptionHTML do
  use LedgrWeb, :html

  embed_templates "subscription_html/*"

  def status_class("active"), do: "status-paid"
  def status_class("paused"), do: "status-partial"
  def status_class("cancelled"), do: "status-unpaid"
  def status_class("expired"), do: "status-unpaid"
  def status_class(_), do: ""

  def plan_label(plan) do
    price =
      if rem(plan.price_cents, 100) == 0 do
        "$#{div(plan.price_cents, 100)}"
      else
        "$#{Float.round(plan.price_cents / 100, 2)}"
      end
    "#{plan.name} — #{price} MXN"
  end

  def plan_type_badge("package"), do: "status-partial"
  def plan_type_badge("promo"), do: "status-partial"
  def plan_type_badge("membership"), do: "status-paid"
  def plan_type_badge("extra"), do: ""
  def plan_type_badge(_), do: ""
end
