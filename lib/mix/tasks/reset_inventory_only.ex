defmodule Mix.Tasks.ResetInventoryOnly do
  use Mix.Task

  alias MrMunchMeAccountingApp.Repo
  alias MrMunchMeAccountingApp.Inventory.{InventoryMovement, InventoryItem}

  @shortdoc "Deletes ALL inventory movements & stock levels (keeps ingredients & locations)"

  def run(_args) do
    Mix.Task.run("app.start")

    IO.puts("\n⚠️  DELETING ALL INVENTORY MOVEMENTS & STOCK ⚠️\n")

    Repo.transaction(fn ->
      Repo.delete_all(InventoryMovement)
      Repo.delete_all(InventoryItem)
    end)

    IO.puts("\n✅ Inventory movements and stock cleared (ingredients & locations kept)\n")
  end
end
