defmodule Ledgr.Core.Reporting do
  @moduledoc """
  Core financial reporting queries that work across all domains.
  Cash flow, P&L aggregation, etc.
  """

  import Ecto.Query, warn: false
  alias Ledgr.Repo

  alias Ledgr.Core.Accounting
  alias Ledgr.Core.Accounting.JournalEntry

  @doc """
  Calculate cash flow for a date range.
  Returns cash inflows, outflows, and net cash flow.
  """
  def cash_flow(start_date, end_date) do
    # Get all cash accounts
    cash_accounts =
      from(a in Accounting.Account,
        where: a.is_cash == true
      )
      |> Repo.all()

    cash_account_ids = Enum.map(cash_accounts, & &1.id)

    # Cash inflows (credits to cash accounts)
    cash_inflows_cents =
      from(je in JournalEntry,
        join: jl in assoc(je, :journal_lines),
        where:
          jl.account_id in ^cash_account_ids and
            jl.credit_cents > 0 and
            je.date >= ^start_date and
            je.date <= ^end_date,
        select: sum(jl.credit_cents)
      )
      |> Repo.one()
      |> case do
        nil -> 0
        total -> total
      end

    # Cash outflows (debits from cash accounts)
    cash_outflows_cents =
      from(je in JournalEntry,
        join: jl in assoc(je, :journal_lines),
        where:
          jl.account_id in ^cash_account_ids and
            jl.debit_cents > 0 and
            je.date >= ^start_date and
            je.date <= ^end_date,
        select: sum(jl.debit_cents)
      )
      |> Repo.one()
      |> case do
        nil -> 0
        total -> total
      end

    # Net cash flow
    net_cash_flow_cents = cash_inflows_cents - cash_outflows_cents

    # Break down by category
    # Inflows: sales, investments, etc.
    sales_inflows_cents =
      from(je in JournalEntry,
        join: jl in assoc(je, :journal_lines),
        where:
          jl.account_id in ^cash_account_ids and
            jl.credit_cents > 0 and
            je.entry_type in ["order_payment", "sale"] and
            je.date >= ^start_date and
            je.date <= ^end_date,
        select: sum(jl.credit_cents)
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
            jl.credit_cents > 0 and
            je.entry_type == "investment" and
            je.date >= ^start_date and
            je.date <= ^end_date,
        select: sum(jl.credit_cents)
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
            jl.debit_cents > 0 and
            je.entry_type in ["expense", "inventory_purchase"] and
            je.date >= ^start_date and
            je.date <= ^end_date,
        select: sum(jl.debit_cents)
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
            jl.debit_cents > 0 and
            je.entry_type == "withdrawal" and
            je.date >= ^start_date and
            je.date <= ^end_date,
        select: sum(jl.debit_cents)
      )
      |> Repo.one()
      |> case do
        nil -> 0
        total -> total
      end

    %{
      period: %{start_date: start_date, end_date: end_date},
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
end
