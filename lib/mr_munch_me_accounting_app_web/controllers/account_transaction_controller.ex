defmodule MrMunchMeAccountingAppWeb.AccountTransactionController do
  use MrMunchMeAccountingAppWeb, :controller

  alias MrMunchMeAccountingApp.Accounting

  def index(conn, params) do
    # Get all accounts
    accounts = Accounting.list_accounts()

    # Get selected account ID from params
    account_id = params["account_id"]

    # If account is selected, get transactions for that account
    {selected_account, transactions, running_balance} =
      if account_id && account_id != "" do
        account_id_int =
          case Integer.parse(account_id) do
            {id, _} -> id
            :error -> nil
          end

        if account_id_int do
          account = Accounting.get_account!(account_id_int)

        # Parse date filters if provided
        date_from =
          case params["date_from"] do
            nil -> nil
            "" -> nil
            date_str -> Date.from_iso8601!(date_str)
          end

        date_to =
          case params["date_to"] do
            nil -> nil
            "" -> nil
            date_str -> Date.from_iso8601!(date_str)
          end

        journal_lines =
          Accounting.list_journal_lines_by_account(account_id_int,
            date_from: date_from,
            date_to: date_to
          )

        # Calculate running balance for each transaction
        transactions_with_balance =
          journal_lines
          |> Enum.reduce({0, []}, fn line, {current_balance, acc} ->
            # Calculate balance after this transaction
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
          |> elem(1)
          |> Enum.reverse()

        # Calculate total running balance (sum of all transactions)
        running_balance =
          journal_lines
          |> Enum.reduce(0, fn line, acc ->
            if account.normal_balance == "debit" do
              acc + line.debit_cents - line.credit_cents
            else
              acc + line.credit_cents - line.debit_cents
            end
          end)

          {account, transactions_with_balance, running_balance}
        else
          {nil, [], 0}
        end
      else
        {nil, [], 0}
      end

    # Build filters
    filters = %{
      account_id: account_id || "",
      date_from:
        if params["all_dates"] == "true" do
          {earliest, _latest} = Accounting.journal_entry_date_range()
          if earliest, do: Date.to_iso8601(earliest), else: ""
        else
          params["date_from"] || ""
        end,
      date_to:
        if params["all_dates"] == "true" do
          {_earliest, latest} = Accounting.journal_entry_date_range()
          if latest, do: Date.to_iso8601(latest), else: ""
        else
          params["date_to"] || ""
        end
    }

    # Re-fetch transactions if all_dates was set
    {selected_account, transactions, running_balance} =
      if params["all_dates"] == "true" && account_id && account_id != "" do
        account_id_int =
          case Integer.parse(account_id) do
            {id, _} -> id
            :error -> nil
          end

        if account_id_int do
          account = Accounting.get_account!(account_id_int)
          {earliest_date, latest_date} = Accounting.journal_entry_date_range()

          date_from = if earliest_date, do: earliest_date, else: nil
          date_to = if latest_date, do: latest_date, else: nil

          journal_lines =
            Accounting.list_journal_lines_by_account(account_id_int,
              date_from: date_from,
              date_to: date_to
            )

          transactions_with_balance =
            journal_lines
            |> Enum.reduce({0, []}, fn line, {current_balance, acc} ->
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
            |> elem(1)
            |> Enum.reverse()

          running_balance =
            journal_lines
            |> Enum.reduce(0, fn line, acc ->
              if account.normal_balance == "debit" do
                acc + line.debit_cents - line.credit_cents
              else
                acc + line.credit_cents - line.debit_cents
              end
            end)

          {account, transactions_with_balance, running_balance}
        else
          {selected_account, transactions, running_balance}
        end
      else
        {selected_account, transactions, running_balance}
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
end

defmodule MrMunchMeAccountingAppWeb.AccountTransactionHTML do
  use MrMunchMeAccountingAppWeb, :html

  embed_templates "account_transaction_html/*"
end
