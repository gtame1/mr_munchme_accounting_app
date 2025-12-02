defmodule Mix.Tasks.ResetAllTables do
  use Mix.Task

  alias MrMunchMeAccountingApp.Repo
  alias MrMunchMeAccountingApp.Accounting.{Account, JournalEntry, JournalLine, MoneyTransfer}
  alias MrMunchMeAccountingApp.Inventory.{InventoryItem, InventoryMovement, Ingredient, Location}
  alias MrMunchMeAccountingApp.Orders.{Order, Product, OrderPayment}
  alias MrMunchMeAccountingApp.Partners.{Partner, CapitalContribution}
  alias MrMunchMeAccountingApp.Expenses.Expense

  @shortdoc "Deletes data from all main tables"

  def run(_args) do
    Mix.Task.run("app.start")

    Repo.transaction(fn ->
      # 1) Children that depend on others
      Repo.delete_all(Expense)
      Repo.delete_all(OrderPayment)
      Repo.delete_all(JournalLine)
      Repo.delete_all(JournalEntry)
      Repo.delete_all(InventoryMovement)
      Repo.delete_all(InventoryItem)
      Repo.delete_all(CapitalContribution)
      Repo.delete_all(MoneyTransfer)

      # 2) Mid-level dependents
      Repo.delete_all(Order)
      Repo.delete_all(Product)
      Repo.delete_all(Ingredient)
      Repo.delete_all(Location)
      Repo.delete_all(Partner)

      # 3) Root tables
      Repo.delete_all(Account)
    end)
  end
end
