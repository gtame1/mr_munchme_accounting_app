defmodule LedgrWeb.AccountTransactionController do
  use LedgrWeb, :controller

  alias Ledgr.Core.Accounting

  def index(conn, params) do
    # Get all accounts
    accounts = Accounting.list_accounts()

    # Get selected account ID from params
    account_id = params["account_id"]

    # Build filters (handle all_dates override)
    filters = build_filters(params, account_id)

    # Parse resolved date filters
    date_from = parse_date(filters.date_from)
    date_to = parse_date(filters.date_to)

    # If account is selected, get transactions for that account
    {selected_account, transactions, running_balance} =
      case parse_account_id(account_id) do
        nil ->
          {nil, [], 0}

        account_id_int ->
          account = Accounting.get_account!(account_id_int)

          journal_lines =
            Accounting.list_journal_lines_by_account(account_id_int,
              date_from: date_from,
              date_to: date_to
            )

          {transactions_with_balance, running_balance} =
            compute_running_balances(journal_lines, account)

          {account, transactions_with_balance, running_balance}
      end

    {earliest_date, latest_date} = Accounting.journal_entry_date_range()

    render(conn, :index,
      accounts: accounts,
      selected_account: selected_account,
      transactions: transactions,
      running_balance: running_balance,
      filters: filters,
      earliest_date: earliest_date,
      latest_date: latest_date
    )
  end

  # Compute running balance by processing oldest-first, then returning newest-first
  defp compute_running_balances(journal_lines, account) do
    # journal_lines come from the query in desc order (newest first).
    # Reverse to oldest-first so we can accumulate the running balance correctly.
    oldest_first = Enum.reverse(journal_lines)

    # Accumulate running balance from oldest to newest.
    # Prepending [row | acc] builds the list in reverse (newest first).
    {running_balance, newest_first} =
      Enum.reduce(oldest_first, {0, []}, fn line, {current_balance, acc} ->
        new_balance =
          if account.normal_balance == "debit" do
            current_balance + line.debit_cents - line.credit_cents
          else
            current_balance + line.credit_cents - line.debit_cents
          end

        row = %{
          line: line,
          balance: new_balance
        }

        {new_balance, [row | acc]}
      end)

    {newest_first, running_balance}
  end

  defp build_filters(params, account_id) do
    if params["all_dates"] == "true" do
      {earliest, latest} = Accounting.journal_entry_date_range()

      %{
        account_id: account_id || "",
        date_from: if(earliest, do: Date.to_iso8601(earliest), else: ""),
        date_to: if(latest, do: Date.to_iso8601(latest), else: "")
      }
    else
      %{
        account_id: account_id || "",
        date_from: params["date_from"] || "",
        date_to: params["date_to"] || ""
      }
    end
  end

  defp parse_account_id(nil), do: nil
  defp parse_account_id(""), do: nil

  defp parse_account_id(id_str) do
    case Integer.parse(id_str) do
      {id, _} -> id
      :error -> nil
    end
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil
  defp parse_date(date_str), do: Date.from_iso8601!(date_str)
end

defmodule LedgrWeb.AccountTransactionHTML do
  use LedgrWeb, :html

  embed_templates "account_transaction_html/*"
end
