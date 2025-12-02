defmodule MrMunchMeAccountingAppWeb.ExpenseController do
  use MrMunchMeAccountingAppWeb, :controller

  alias MrMunchMeAccountingApp.Expenses
  alias MrMunchMeAccountingApp.Expenses.Expense
  alias MrMunchMeAccountingApp.Accounting

  def index(conn, _params) do
    expenses = Expenses.list_expenses()

    render(conn, :index, expenses: expenses)
  end

  def new(conn, _params) do
    changeset = Expenses.change_expense(%Expense{})

    render(conn, :new,
      changeset: changeset,
      action: ~p"/expenses",
      expense_account_options: Accounting.expense_account_options(),
      paid_from_account_options: Accounting.cash_or_payable_account_options()
    )
  end

  def create(conn, %{"expense" => attrs}) do
    case Expenses.create_expense_with_journal(attrs) do
      {:ok, expense} ->
        conn
        |> put_flash(:info, "Expense recorded.")
        |> redirect(to: ~p"/expenses/#{expense.id}")

      {:error, %Ecto.Changeset{} = changeset} ->
        changeset = Map.put(changeset, :action, :insert)

        render(conn, :new,
          changeset: changeset,
          action: ~p"/expenses",
          expense_account_options: Accounting.expense_account_options(),
          paid_from_account_options: Accounting.cash_or_payable_account_options()
        )
    end
  end

  def show(conn, %{"id" => id}) do
    expense = Expenses.get_expense!(id)

    render(conn, :show, expense: expense)
  end

  def delete(conn, %{"id" => id}) do
    expense = Expenses.get_expense!(id)

    case Expenses.delete_expense(expense) do
      {:ok, _expense} ->
        conn
        |> put_flash(:info, "Expense deleted successfully.")
        |> redirect(to: ~p"/expenses")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Failed to delete expense.")
        |> redirect(to: ~p"/expenses/#{expense.id}")
    end
  end
end


defmodule MrMunchMeAccountingAppWeb.ExpenseHTML do
  use MrMunchMeAccountingAppWeb, :html
  import MrMunchMeAccountingAppWeb.CoreComponents

  embed_templates "expense_html/*"
end
