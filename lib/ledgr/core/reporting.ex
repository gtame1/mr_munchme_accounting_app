defmodule Ledgr.Core.Reporting do
  @moduledoc """
  Core financial reporting queries that work across all domains.
  Cash flow, P&L aggregation, etc.
  """

  import Ecto.Query, warn: false
  alias Ledgr.Repo

  alias Ledgr.Core.Accounting
  alias Ledgr.Core.Accounting.{JournalEntry, JournalLine}

  @doc """
  Calculate cash flow for a date range.
  Returns cash inflows, outflows, net cash flow, and beginning/ending balances.

  Cash accounts are debit-normal assets:
  - Debit to cash = money coming IN (inflow)
  - Credit to cash = money going OUT (outflow)

  Internal transfers between cash accounts are excluded from
  inflow/outflow totals since they don't represent real cash movement.
  """
  def cash_flow(start_date, end_date) do
    # Get all cash accounts
    cash_accounts =
      from(a in Accounting.Account,
        where: a.is_cash == true
      )
      |> Repo.all()

    cash_account_ids = Enum.map(cash_accounts, & &1.id)

    # Beginning and ending cash balances
    beginning_balance_cents =
      cash_balance_as_of(cash_account_ids, Date.add(start_date, -1))

    ending_balance_cents =
      cash_balance_as_of(cash_account_ids, end_date)

    # Cash inflows = debits to cash accounts (money received)
    # Exclude internal transfers (cash-to-cash moves inflate both sides)
    cash_inflows_cents =
      from(je in JournalEntry,
        join: jl in assoc(je, :journal_lines),
        where:
          jl.account_id in ^cash_account_ids and
            jl.debit_cents > 0 and
            je.entry_type != "internal_transfer" and
            je.date >= ^start_date and
            je.date <= ^end_date,
        select: sum(jl.debit_cents)
      )
      |> Repo.one()
      |> case do
        nil -> 0
        total -> total
      end

    # Cash outflows = credits to cash accounts (money paid out)
    cash_outflows_cents =
      from(je in JournalEntry,
        join: jl in assoc(je, :journal_lines),
        where:
          jl.account_id in ^cash_account_ids and
            jl.credit_cents > 0 and
            je.entry_type != "internal_transfer" and
            je.date >= ^start_date and
            je.date <= ^end_date,
        select: sum(jl.credit_cents)
      )
      |> Repo.one()
      |> case do
        nil -> 0
        total -> total
      end

    # Net cash flow
    net_cash_flow_cents = cash_inflows_cents - cash_outflows_cents

    # Break down by category
    # Inflows: order payments, investments
    sales_inflows_cents =
      from(je in JournalEntry,
        join: jl in assoc(je, :journal_lines),
        where:
          jl.account_id in ^cash_account_ids and
            jl.debit_cents > 0 and
            je.entry_type == "order_payment" and
            je.date >= ^start_date and
            je.date <= ^end_date,
        select: sum(jl.debit_cents)
      )
      |> Repo.one()
      |> case do
        nil -> 0
        total -> total
      end

    investment_inflows_cents =
      from(je in JournalEntry,
        join: jl in assoc(je, :journal_lines),
        where:
          jl.account_id in ^cash_account_ids and
            jl.debit_cents > 0 and
            je.entry_type == "investment" and
            je.date >= ^start_date and
            je.date <= ^end_date,
        select: sum(jl.debit_cents)
      )
      |> Repo.one()
      |> case do
        nil -> 0
        total -> total
      end

    # Outflows: expenses, inventory purchases, withdrawals
    expense_outflows_cents =
      from(je in JournalEntry,
        join: jl in assoc(je, :journal_lines),
        where:
          jl.account_id in ^cash_account_ids and
            jl.credit_cents > 0 and
            je.entry_type in ["expense", "inventory_purchase"] and
            je.date >= ^start_date and
            je.date <= ^end_date,
        select: sum(jl.credit_cents)
      )
      |> Repo.one()
      |> case do
        nil -> 0
        total -> total
      end

    withdrawal_outflows_cents =
      from(je in JournalEntry,
        join: jl in assoc(je, :journal_lines),
        where:
          jl.account_id in ^cash_account_ids and
            jl.credit_cents > 0 and
            je.entry_type == "withdrawal" and
            je.date >= ^start_date and
            je.date <= ^end_date,
        select: sum(jl.credit_cents)
      )
      |> Repo.one()
      |> case do
        nil -> 0
        total -> total
      end

    %{
      period: %{start_date: start_date, end_date: end_date},
      beginning_balance_cents: beginning_balance_cents,
      ending_balance_cents: ending_balance_cents,
      cash_inflows_cents: cash_inflows_cents,
      cash_outflows_cents: cash_outflows_cents,
      net_cash_flow_cents: net_cash_flow_cents,
      breakdown: %{
        sales_inflows_cents: sales_inflows_cents,
        investment_inflows_cents: investment_inflows_cents,
        expense_outflows_cents: expense_outflows_cents,
        withdrawal_outflows_cents: withdrawal_outflows_cents,
        other_inflows_cents: cash_inflows_cents - sales_inflows_cents - investment_inflows_cents,
        other_outflows_cents: cash_outflows_cents - expense_outflows_cents - withdrawal_outflows_cents
      }
    }
  end

  # Calculate total cash balance as of a given date.
  # Cash accounts are debit-normal: balance = sum(debits) - sum(credits).
  defp cash_balance_as_of(cash_account_ids, as_of_date) do
    from(jl in JournalLine,
      join: je in JournalEntry,
      on: jl.journal_entry_id == je.id,
      where:
        jl.account_id in ^cash_account_ids and
          je.date <= ^as_of_date,
      select: coalesce(sum(jl.debit_cents), 0) - coalesce(sum(jl.credit_cents), 0)
    )
    |> Repo.one()
    |> case do
      nil -> 0
      total -> total
    end
  end
end
