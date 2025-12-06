defmodule Mix.Tasks.BackfillMovementCosts do
  @moduledoc """
  Backfills costs for inventory movements that have $0 cost.

  This is useful when movements were recorded before purchases were added.
  """
  use Mix.Task

  @shortdoc "Backfills costs for inventory movements with $0 cost"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    alias MrMunchMeAccountingApp.Inventory

    IO.puts("🔍 Finding movements with $0 cost...")

    case Inventory.backfill_movement_costs() do
      {:ok, count} ->
        IO.puts("✅ Successfully updated #{count} movement(s) with correct costs.")

      {:error, reason} ->
        IO.puts("❌ Error: #{inspect(reason)}")
    end
  end
end
