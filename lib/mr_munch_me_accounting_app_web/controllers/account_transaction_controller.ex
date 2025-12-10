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
      date_from: params["date_from"] || "",
      date_to: params["date_to"] || ""
    }

    render(conn, :index,
      accounts: accounts,
      selected_account: selected_account,
      transactions: transactions,
      running_balance: running_balance,
      filters: filters
    )
  end
end

defmodule MrMunchMeAccountingAppWeb.AccountTransactionHTML do
  use MrMunchMeAccountingAppWeb, :html
  import MrMunchMeAccountingAppWeb.CoreComponents

  embed_templates "account_transaction_html/*"
end
