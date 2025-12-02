defmodule MrMunchMeAccountingAppWeb.TransferController do
  use MrMunchMeAccountingAppWeb, :controller

  alias MrMunchMeAccountingApp.Accounting

  def index(conn, _params) do
    transfers = Accounting.list_money_transfers()

    render(conn, :index,
      transfers: transfers
    )
  end

  def new(conn, _params) do
    changeset = Accounting.change_transfer_form(%{})

    render(conn, :new,
      changeset: changeset,
      account_options: Accounting.cash_or_payable_account_options()
    )
  end

  def create(conn, %{"transfer" => params}) do
    case Accounting.create_money_transfer(params) do
      {:ok, _transfer} ->
        conn
        |> put_flash(:info, "Transfer recorded successfully.")
        |> redirect(to: ~p"/transfers")

      {:error, changeset} ->
        changeset = %{changeset | action: :insert}

        render(conn, :new,
          changeset: changeset,
          account_options: Accounting.cash_or_payable_account_options()
        )
    end
  end
end


defmodule MrMunchMeAccountingAppWeb.TransferHTML do
  use MrMunchMeAccountingAppWeb, :html
  import MrMunchMeAccountingAppWeb.CoreComponents

  embed_templates "transfer_html/*"
end
