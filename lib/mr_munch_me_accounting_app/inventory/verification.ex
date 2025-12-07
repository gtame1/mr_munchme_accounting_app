defmodule MrMunchMeAccountingApp.Inventory.Verification do
  @moduledoc """
  Verification functions to ensure inventory accounting integrity.
  """
  require Logger
  import Ecto.Query
  alias MrMunchMeAccountingApp.{Repo, Accounting}
  alias MrMunchMeAccountingApp.Accounting.{JournalEntry, JournalLine}
  alias MrMunchMeAccountingApp.Inventory.{Ingredient, Location, InventoryItem, InventoryMovement}

  @ingredients_account_code "1200"
  @wip_account_code "1220"

  @doc """
  Verifies that inventory quantities match movements.
  Returns {:ok, []} if all good, {:error, issues} if problems found.
  """
  def verify_inventory_quantities do
    issues = []

    # Check each inventory item with preloaded ingredient and location
    items =
      from(ii in InventoryItem,
        preload: [:ingredient, :location]
      )
      |> Repo.all()

    issues =
      Enum.reduce(items, issues, fn item, acc ->
        calculated_qty = calculate_quantity_from_movements(item.ingredient_id, item.location_id)

        if item.quantity_on_hand != calculated_qty do
          ingredient_name = item.ingredient.name || "Unknown"
          location_name = item.location.name || "Unknown"

          [
            "Inventory mismatch: #{ingredient_name} @ #{location_name} - " <>
            "System: #{item.quantity_on_hand}, Calculated: #{calculated_qty}"
            | acc
          ]
        else
          acc
        end
      end)

    if issues == [] do
      {:ok, %{checked_items: length(items), issues: []}}
    else
      {:error, issues}
    end
  end

  @doc """
  Verifies that WIP account balance matches sum of in_prep orders.
  """
  def verify_wip_balance do
    wip_account = Accounting.get_account_by_code!(@wip_account_code)
    wip_balance = get_account_balance(wip_account.id)

    # Sum all WIP debits from order_in_prep entries
    calculated_wip =
      from(je in JournalEntry,
        join: jl in assoc(je, :journal_lines),
        where: je.entry_type == "order_in_prep",
        where: jl.account_id == ^wip_account.id,
        where: jl.debit_cents > 0,
        select: fragment("COALESCE(SUM(?), 0)", jl.debit_cents)
      )
      |> Repo.one()
      |> case do
        val when is_integer(val) -> val
        %Decimal{} = val -> Decimal.to_integer(val)
        _ -> 0
      end

    # Sum all WIP credits from order_delivered entries
    wip_credits =
      from(je in JournalEntry,
        join: jl in assoc(je, :journal_lines),
        where: je.entry_type == "order_delivered",
        where: jl.account_id == ^wip_account.id,
        where: jl.credit_cents > 0,
        select: fragment("COALESCE(SUM(?), 0)", jl.credit_cents)
      )
      |> Repo.one()
      |> case do
        val when is_integer(val) -> val
        %Decimal{} = val -> Decimal.to_integer(val)
        _ -> 0
      end

    net_wip = calculated_wip - wip_credits

    if wip_balance == net_wip do
      {:ok, %{wip_balance: wip_balance, calculated: net_wip, debits: calculated_wip, credits: wip_credits}}
    else
      {:error, "WIP balance mismatch: Account=#{format_currency(wip_balance)}, Calculated=#{format_currency(net_wip)} (Debits: #{format_currency(calculated_wip)}, Credits: #{format_currency(wip_credits)})"}
    end
  end

  @doc """
  Verifies that inventory cost values match journal entries.
  """
  def verify_inventory_cost_accounting do
    ingredients_account = Accounting.get_account_by_code!(@ingredients_account_code)

    # Calculate inventory value from InventoryItem records
    inventory_value =
      from(ii in InventoryItem,
        select: fragment("COALESCE(SUM(? * ?), 0)",
          ii.quantity_on_hand,
          ii.avg_cost_per_unit_cents)
      )
      |> Repo.one()
      |> case do
        val when is_integer(val) -> val
        %Decimal{} = val -> Decimal.to_integer(val)
        _ -> 0
      end

    # Calculate inventory value from journal entries
    account_balance = get_account_balance(ingredients_account.id)

    # Allow 1 peso difference for rounding (100 cents)
    if abs(inventory_value - account_balance) < 100 do
      {:ok, %{inventory_value: inventory_value, account_balance: account_balance, difference: abs(inventory_value - account_balance)}}
    else
      {:error, "Inventory value mismatch: Items=#{format_currency(inventory_value)}, Account=#{format_currency(account_balance)}, Difference=#{format_currency(abs(inventory_value - account_balance))}"}
    end
  end

  @doc """
  Verifies that all order_in_prep entries have matching order_delivered entries
  (or orders are still in_prep).
  """
  def verify_order_wip_consistency do
    # Get all order_in_prep entries
    in_prep_orders =
      from(je in JournalEntry,
        where: je.entry_type == "order_in_prep",
        select: je.reference
      )
      |> Repo.all()
      |> Enum.map(fn ref ->
        case Regex.run(~r/Order #(\d+)/, ref) do
          [_, order_id] -> String.to_integer(order_id)
          _ -> nil
        end
      end)
      |> Enum.filter(& &1)

    # Check each order
    issues =
      Enum.reduce(in_prep_orders, [], fn order_id, acc ->
        # Check if order has been delivered
        has_delivered_entry =
          from(je in JournalEntry,
            where: je.entry_type == "order_delivered",
            where: je.reference == ^"Order ##{order_id}"
          )
          |> Repo.exists?()

        if has_delivered_entry do
          # Verify WIP was properly relieved
          wip_debit = get_wip_debit_for_order(order_id)
          wip_credit = get_wip_credit_for_order(order_id)

          if wip_debit != wip_credit do
            ["Order ##{order_id}: WIP debit (#{wip_debit}) != credit (#{wip_credit})" | acc]
          else
            acc
          end
        else
          # Order is still in_prep, which is fine
          acc
        end
      end)

    if issues == [] do
      {:ok, %{checked_orders: length(in_prep_orders), issues: []}}
    else
      {:error, issues}
    end
  end

  @doc """
  Verifies that all journal entries are balanced.
  """
  def verify_journal_entries_balanced do
    unbalanced_entries =
      from(je in JournalEntry,
        preload: :journal_lines
      )
      |> Repo.all()
      |> Enum.filter(fn entry ->
        total_debits =
          entry.journal_lines
          |> Enum.map(& &1.debit_cents)
          |> Enum.sum()

        total_credits =
          entry.journal_lines
          |> Enum.map(& &1.credit_cents)
          |> Enum.sum()

        total_debits != total_credits
      end)

    if unbalanced_entries == [] do
      {:ok, %{checked_entries: Repo.aggregate(JournalEntry, :count, :id), unbalanced: 0}}
    else
      issues =
        Enum.map(unbalanced_entries, fn entry ->
          total_debits =
            entry.journal_lines
            |> Enum.map(& &1.debit_cents)
            |> Enum.sum()

          total_credits =
            entry.journal_lines
            |> Enum.map(& &1.credit_cents)
            |> Enum.sum()

          "Journal Entry ##{entry.id} (#{entry.entry_type}): Debits=#{total_debits}, Credits=#{total_credits}"
        end)

      {:error, issues}
    end
  end

  @doc """
  Runs all verification checks and returns a report.
  """
  def run_all_checks do
    %{
      inventory_quantities: verify_inventory_quantities(),
      wip_balance: verify_wip_balance(),
      inventory_cost_accounting: verify_inventory_cost_accounting(),
      order_wip_consistency: verify_order_wip_consistency(),
      journal_entries_balanced: verify_journal_entries_balanced()
    }
  end

  @doc """
  Repairs inventory quantities by recalculating from movements and updating InventoryItem records.

  This function:
  1. Recalculates the correct quantity for each inventory item based on movements
  2. Updates the InventoryItem.quantity_on_hand to match the calculated value
  3. Returns a report of what was fixed

  Use this when verify_inventory_quantities() shows mismatches.
  """
  def repair_inventory_quantities do
    Repo.transaction(fn ->
      # Get all inventory items with preloaded ingredient and location
      items =
        from(ii in InventoryItem,
          preload: [:ingredient, :location]
        )
        |> Repo.all()

      repairs =
        Enum.reduce(items, [], fn item, acc ->
          calculated_qty = calculate_quantity_from_movements(item.ingredient_id, item.location_id)

          if item.quantity_on_hand != calculated_qty do
            # Update the quantity
            item
            |> InventoryItem.changeset(%{quantity_on_hand: calculated_qty})
            |> Repo.update!()

            [
              %{
                ingredient: item.ingredient.name,
                location: item.location.name,
                old_quantity: item.quantity_on_hand,
                new_quantity: calculated_qty,
                difference: calculated_qty - item.quantity_on_hand
              }
              | acc
            ]
          else
            acc
          end
        end)

      repairs
    end)
  end

  # Helper functions

  # Make calculate_quantity_from_movements public so it can be used by repair function
  def calculate_quantity_from_movements(ingredient_id, location_id) do
    purchases =
      from(m in InventoryMovement,
        where: m.ingredient_id == ^ingredient_id,
        where: m.to_location_id == ^location_id,
        where: m.movement_type == "purchase",
        select: fragment("COALESCE(SUM(?), 0)", m.quantity)
      )
      |> Repo.one()
      |> case do
        val when is_integer(val) -> val
        %Decimal{} = val -> Decimal.to_integer(val)
        _ -> 0
      end

    usages =
      from(m in InventoryMovement,
        where: m.ingredient_id == ^ingredient_id,
        where: m.from_location_id == ^location_id,
        where: m.movement_type in ["usage", "write_off"],
        select: fragment("COALESCE(SUM(?), 0)", m.quantity)
      )
      |> Repo.one()
      |> case do
        val when is_integer(val) -> val
        %Decimal{} = val -> Decimal.to_integer(val)
        _ -> 0
      end

    transfers_in =
      from(m in InventoryMovement,
        where: m.ingredient_id == ^ingredient_id,
        where: m.to_location_id == ^location_id,
        where: m.movement_type == "transfer",
        select: fragment("COALESCE(SUM(?), 0)", m.quantity)
      )
      |> Repo.one()
      |> case do
        val when is_integer(val) -> val
        %Decimal{} = val -> Decimal.to_integer(val)
        _ -> 0
      end

    transfers_out =
      from(m in InventoryMovement,
        where: m.ingredient_id == ^ingredient_id,
        where: m.from_location_id == ^location_id,
        where: m.movement_type == "transfer",
        select: fragment("COALESCE(SUM(?), 0)", m.quantity)
      )
      |> Repo.one()
      |> case do
        val when is_integer(val) -> val
        %Decimal{} = val -> Decimal.to_integer(val)
        _ -> 0
      end

    purchases + transfers_in - usages - transfers_out
  end

  defp get_account_balance(account_id) do
    result =
      from(jl in JournalLine,
        where: jl.account_id == ^account_id,
        select: %{
          total_debits: fragment("COALESCE(SUM(?), 0)", jl.debit_cents),
          total_credits: fragment("COALESCE(SUM(?), 0)", jl.credit_cents)
        }
      )
      |> Repo.one()

    debits = case result do
      %{total_debits: d} when is_integer(d) -> d
      %{total_debits: %Decimal{} = d} -> Decimal.to_integer(d)
      _ -> 0
    end

    credits = case result do
      %{total_credits: c} when is_integer(c) -> c
      %{total_credits: %Decimal{} = c} -> Decimal.to_integer(c)
      _ -> 0
    end

    debits - credits  # For asset accounts
  end

  defp get_wip_debit_for_order(order_id) do
    reference = "Order ##{order_id}"
    wip_account = Accounting.get_account_by_code!(@wip_account_code)

    from(je in JournalEntry,
      join: jl in assoc(je, :journal_lines),
      where: je.entry_type == "order_in_prep",
      where: je.reference == ^reference,
      where: jl.account_id == ^wip_account.id,
      where: jl.debit_cents > 0,
      select: jl.debit_cents,
      limit: 1
    )
    |> Repo.one() || 0
  end

  defp get_wip_credit_for_order(order_id) do
    reference = "Order ##{order_id}"
    wip_account = Accounting.get_account_by_code!(@wip_account_code)

    from(je in JournalEntry,
      join: jl in assoc(je, :journal_lines),
      where: je.entry_type == "order_delivered",
      where: je.reference == ^reference,
      where: jl.account_id == ^wip_account.id,
      where: jl.credit_cents > 0,
      select: jl.credit_cents,
      limit: 1
    )
    |> Repo.one() || 0
  end

  # Helper function to format cents as currency
  defp format_currency(cents) when is_integer(cents) do
    abs_cents = abs(cents)
    pesos = div(abs_cents, 100)
    cents_remainder = rem(abs_cents, 100)
    sign = if cents < 0, do: "-", else: ""
    "#{sign}#{pesos}.#{String.pad_leading(Integer.to_string(cents_remainder), 2, "0")} MXN"
  end

  defp format_currency(_), do: "0.00 MXN"
end
