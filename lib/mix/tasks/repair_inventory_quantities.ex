defmodule Mix.Tasks.RepairInventoryQuantities do
  @moduledoc """
  Repairs inventory quantities by recalculating from movements.

  Usage: mix repair_inventory_quantities
  """
  use Mix.Task

  alias Ledgr.Domains.MrMunchMe.Inventory.Verification

  @shortdoc "Repairs inventory quantities by recalculating from movements"

  def run(_args) do
    Mix.Task.run("app.start")

    IO.puts("\n🔧 Repairing inventory quantities...\n")
    IO.puts(String.duplicate("=", 60))
    IO.puts("")

    case Verification.repair_inventory_quantities() do
      {:ok, repairs} ->
        if repairs == [] do
          IO.puts("✅ All inventory quantities are already correct. No repairs needed.")
        else
          IO.puts("✅ Repaired #{length(repairs)} inventory item(s):\n")

          Enum.each(repairs, fn repair ->
            IO.puts("  • #{repair.ingredient} @ #{repair.location}")
            IO.puts("    Old: #{repair.old_quantity} → New: #{repair.new_quantity} (difference: #{repair.difference})")
            IO.puts("")
          end)

          IO.puts("✨ Repair completed successfully!")
        end

      {:error, reason} ->
        IO.puts("❌ Repair failed: #{inspect(reason)}")
        System.halt(1)
    end

    IO.puts(String.duplicate("=", 60))
  end
end
