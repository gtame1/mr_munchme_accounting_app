defmodule Ledgr.Domains.Viaxe.Bookings.BookingAccounting do
  @moduledoc """
  Accounting integration for the Viaxe booking lifecycle.

  Records double-entry journal entries for each billable event using a
  deferred-revenue model:

    - Confirmed  → DR AR (1100)               / CR Customer Deposits (2200)
    - Payment    → DR Cash (1000 or linked)   / CR AR (1100)
    - Completed  → DR Customer Deposits (2200) / CR Commission Revenue (4000)
                                              + CR Supplier Payables (2100)
    - Canceled   → DR Customer Deposits (2200) / CR AR (1100)

  Revenue is only recognised (account 4000) when the trip is completed,
  limited to the agency's commission (`commission_cents`).  The supplier
  cost (`total_cost_cents`) flows to Supplier Payables (2100).

  All functions are idempotent: calling the same function twice for the same
  booking / payment will return the existing entry rather than creating a
  duplicate.
  """

  import Ecto.Query, warn: false

  alias Ledgr.Repo
  alias Ledgr.Core.Accounting
  alias Ledgr.Core.Accounting.{JournalEntry, Account}

  @cash_code             "1000"
  @ar_code               "1100"
  @supplier_payables_code "2100"
  @customer_deposits_code "2200"
  @commission_revenue_code "4000"

  # ── Status-change dispatcher ─────────────────────────────────────────────

  def handle_status_change(booking, "confirmed"), do: record_booking_confirmed(booking)
  def handle_status_change(booking, "completed"), do: record_booking_completed(booking)
  def handle_status_change(booking, "canceled"),  do: record_booking_canceled(booking)
  def handle_status_change(_booking, _status),    do: {:ok, nil}

  # ── Booking Confirmed ────────────────────────────────────────────────────
  # DR AR (1100)  /  CR Customer Deposits (2200)  →  total_price_cents

  def record_booking_confirmed(%{id: id, total_price_cents: price}) do
    reference  = "viaxe_booking_#{id}_confirmed"
    entry_type = "booking_created"

    existing =
      from(je in JournalEntry,
        where: je.entry_type == ^entry_type and je.reference == ^reference
      )
      |> Repo.one()

    if existing do
      {:ok, existing}
    else
      ar      = Accounting.get_account_by_code!(@ar_code)
      deposit = Accounting.get_account_by_code!(@customer_deposits_code)

      Accounting.create_journal_entry_with_lines(
        %{
          date:        Date.utc_today(),
          description: "Booking ##{id} confirmed",
          reference:   reference,
          entry_type:  entry_type
        },
        [
          %{account_id: ar.id,      debit_cents: price, credit_cents: 0,
            description: "AR — booking #{id}"},
          %{account_id: deposit.id, debit_cents: 0,     credit_cents: price,
            description: "Customer deposit — booking #{id}"}
        ]
      )
    end
  end

  # ── Payment Received ─────────────────────────────────────────────────────
  # DR Cash (1000 or linked account)  /  CR AR (1100)  →  amount_cents

  def record_booking_payment(%{id: pay_id, booking_id: b_id, amount_cents: amt,
                                cash_account_id: cash_account_id}) do
    reference  = "viaxe_payment_#{pay_id}"
    entry_type = "booking_payment"

    existing =
      from(je in JournalEntry,
        where: je.entry_type == ^entry_type and je.reference == ^reference
      )
      |> Repo.one()

    if existing do
      {:ok, existing}
    else
      cash =
        if cash_account_id,
          do:   Repo.get!(Account, cash_account_id),
          else: Accounting.get_account_by_code!(@cash_code)

      ar = Accounting.get_account_by_code!(@ar_code)

      Accounting.create_journal_entry_with_lines(
        %{
          date:        Date.utc_today(),
          description: "Payment on booking ##{b_id}",
          reference:   reference,
          entry_type:  entry_type
        },
        [
          %{account_id: cash.id, debit_cents: amt, credit_cents: 0,
            description: "Cash received — booking #{b_id}"},
          %{account_id: ar.id,   debit_cents: 0,   credit_cents: amt,
            description: "Reduce AR — booking #{b_id}"}
        ]
      )
    end
  end

  # ── Booking Completed ────────────────────────────────────────────────────
  # DR Customer Deposits (2200)  /  CR Commission Revenue (4000, commission_cents)
  #                              +  CR Supplier Payables  (2100, total_cost_cents)
  #
  # Invariant: total_price_cents = commission_cents + total_cost_cents

  def record_booking_completed(%{id: id, total_price_cents: price,
                                  commission_cents: comm, total_cost_cents: cost}) do
    reference  = "viaxe_booking_#{id}_completed"
    entry_type = "booking_completed"

    existing =
      from(je in JournalEntry,
        where: je.entry_type == ^entry_type and je.reference == ^reference
      )
      |> Repo.one()

    if existing do
      {:ok, existing}
    else
      deposit = Accounting.get_account_by_code!(@customer_deposits_code)
      revenue = Accounting.get_account_by_code!(@commission_revenue_code)
      payable = Accounting.get_account_by_code!(@supplier_payables_code)

      Accounting.create_journal_entry_with_lines(
        %{
          date:        Date.utc_today(),
          description: "Booking ##{id} completed",
          reference:   reference,
          entry_type:  entry_type
        },
        [
          %{account_id: deposit.id, debit_cents: price, credit_cents: 0,
            description: "Release customer deposit — booking #{id}"},
          %{account_id: revenue.id, debit_cents: 0,     credit_cents: comm,
            description: "Commission revenue — booking #{id}"},
          %{account_id: payable.id, debit_cents: 0,     credit_cents: cost,
            description: "Supplier payable — booking #{id}"}
        ]
      )
    end
  end

  # ── Booking Canceled ─────────────────────────────────────────────────────
  # DR Customer Deposits (2200)  /  CR AR (1100)  →  total_price_cents
  # Reverses the original confirmation entry.

  def record_booking_canceled(%{id: id, total_price_cents: price}) do
    reference  = "viaxe_booking_#{id}_canceled"
    entry_type = "booking_canceled"

    existing =
      from(je in JournalEntry,
        where: je.entry_type == ^entry_type and je.reference == ^reference
      )
      |> Repo.one()

    if existing do
      {:ok, existing}
    else
      deposit = Accounting.get_account_by_code!(@customer_deposits_code)
      ar      = Accounting.get_account_by_code!(@ar_code)

      Accounting.create_journal_entry_with_lines(
        %{
          date:        Date.utc_today(),
          description: "Booking ##{id} canceled",
          reference:   reference,
          entry_type:  entry_type
        },
        [
          %{account_id: deposit.id, debit_cents: price, credit_cents: 0,
            description: "Reverse deposit — booking #{id}"},
          %{account_id: ar.id,      debit_cents: 0,     credit_cents: price,
            description: "Reverse AR — booking #{id}"}
        ]
      )
    end
  end
end
