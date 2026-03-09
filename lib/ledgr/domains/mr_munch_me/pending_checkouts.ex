defmodule Ledgr.Domains.MrMunchMe.PendingCheckouts do
  alias Ledgr.Repo
  alias Ledgr.Domains.MrMunchMe.PendingCheckout

  def create(cart, customer_id, checkout_attrs) do
    expires_at = NaiveDateTime.add(NaiveDateTime.utc_now(), 86_400, :second)

    %PendingCheckout{}
    |> PendingCheckout.changeset(%{
      cart: cart,
      customer_id: customer_id,
      checkout_attrs: checkout_attrs,
      expires_at: expires_at
    })
    |> Repo.insert()
  end

  def set_stripe_session(pending_checkout, stripe_session_id) do
    pending_checkout
    |> PendingCheckout.changeset(%{stripe_session_id: stripe_session_id})
    |> Repo.update()
  end

  def get_by_id(id) do
    Repo.get(PendingCheckout, id)
  end

  def get_by_stripe_session(stripe_session_id) do
    Repo.get_by(PendingCheckout, stripe_session_id: stripe_session_id)
  end

  def mark_processed(pending_checkout) do
    pending_checkout
    |> PendingCheckout.changeset(%{processed_at: NaiveDateTime.utc_now()})
    |> Repo.update()
  end

  def already_processed?(%PendingCheckout{processed_at: nil}), do: false
  def already_processed?(%PendingCheckout{}), do: true
end
