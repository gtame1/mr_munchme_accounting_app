defmodule LedgrWeb.Domains.CasaTame.CardCreditController do
  use LedgrWeb, :controller

  alias Ledgr.Core.Accounting
  alias Ledgr.Repo
  import Ecto.Query

  # GET /app/casa-tame/card-credits/new?account_id=123
  def new(conn, params) do
    account_id = params["account_id"]

    selected_account =
      case account_id do
        nil -> nil
        "" -> nil
        id -> Accounting.get_account!(String.to_integer(id))
      end

    render(conn, :new,
      selected_account: selected_account,
      credit_card_options: credit_card_options(),
      credit_to_options: credit_to_options(),
      today: Ledgr.Domains.CasaTame.today()
    )
  end

  # POST /app/casa-tame/card-credits
  def create(conn, %{"card_credit" => params}) do
    account_id = String.to_integer(params["account_id"])
    credit_to_id = String.to_integer(params["credit_to_account_id"])
    amount_str = params["amount"] || "0"
    amount_cents = round(String.to_float(amount_str) * 100)
    description = params["description"] || "Card Credit"
    date = Date.from_iso8601!(params["date"])

    card_account = Accounting.get_account!(account_id)
    credit_to_account = Accounting.get_account!(credit_to_id)

    entry_attrs = %{
      date: date,
      description: description,
      entry_type: "card_credit",
      reference: "CardCredit #{Date.to_iso8601(date)}"
    }

    # DR credit_card (reduces liability) / CR credit_to_account (income or expense offset)
    lines = [
      %{
        account_id: card_account.id,
        debit_cents: amount_cents,
        credit_cents: 0,
        description: description
      },
      %{
        account_id: credit_to_account.id,
        debit_cents: 0,
        credit_cents: amount_cents,
        description: description
      }
    ]

    case Accounting.create_journal_entry_with_lines(entry_attrs, lines) do
      {:ok, _entry} ->
        conn
        |> put_flash(:info, "Card credit recorded successfully.")
        |> redirect(to: dp(conn, "/account-transactions?account_id=#{account_id}"))

      {:error, changeset} ->
        conn
        |> put_flash(:error, "Error: #{inspect(changeset.errors)}")
        |> render(:new,
          selected_account: Accounting.get_account!(account_id),
          credit_card_options: credit_card_options(),
          credit_to_options: credit_to_options(),
          today: Ledgr.Domains.CasaTame.today()
        )
    end
  end

  # ── Private ─────────────────────────────────────────────────

  defp credit_card_options do
    alias Ledgr.Core.Accounting.Account

    Repo.all(
      from a in Account,
        where: a.type == "liability" and a.code >= "2000" and a.code <= "2109",
        order_by: a.code
    )
    |> Enum.map(&{"#{&1.code} – #{&1.name}", &1.id})
  end

  defp credit_to_options do
    alias Ledgr.Core.Accounting.Account

    income_accounts =
      Repo.all(
        from a in Account,
          where: a.type == "revenue",
          order_by: a.code
      )

    expense_accounts =
      Repo.all(
        from a in Account,
          where: a.type == "expense" and a.code >= "6000" and a.code <= "6199",
          order_by: a.code
      )

    income_opts = Enum.map(income_accounts, &{"Income: #{&1.name}", &1.id})
    expense_opts = Enum.map(expense_accounts, &{"Expense offset: #{&1.name}", &1.id})

    income_opts ++ expense_opts
  end
end

defmodule LedgrWeb.Domains.CasaTame.CardCreditHTML do
  use LedgrWeb, :html
  embed_templates "card_credit_html/*"
end
