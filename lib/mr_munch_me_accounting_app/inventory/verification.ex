defmodule MrMunchMeAccountingApp.Inventory.Verification do
  @moduledoc """
  Verification functions to ensure inventory accounting integrity.
  """
  require Logger
  import Ecto.Query
  alias MrMunchMeAccountingApp.{Repo, Accounting, Inventory}
  alias MrMunchMeAccountingApp.Accounting.{Account, JournalEntry, JournalLine}
  alias MrMunchMeAccountingApp.Inventory.{Ingredient, InventoryItem, InventoryMovement}
  alias MrMunchMeAccountingApp.Orders.Order

  @ingredients_account_code "1200"
  @wip_account_code "1220"
  @ar_code "1100"
  @customer_deposits_code "2200"
  @owners_equity_code "3000"
  @owners_drawings_code "3100"
  @gift_contributions_code "4100"
  @waste_shrinkage_code "6060"
  @samples_gifts_code "6070"

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
  Verifies that WIP account is internally consistent.
  Reports the current WIP balance and number of orders in prep.
  """
  def verify_wip_balance do
    wip_account = Accounting.get_account_by_code!(@wip_account_code)

    # Get all debits and credits to WIP account (regardless of entry type)
    result =
      from(jl in JournalLine,
        where: jl.account_id == ^wip_account.id,
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

    wip_balance = debits - credits

    # Count orders currently in prep (have order_in_prep but no order_delivered)
    orders_in_prep = count_orders_in_prep()

    {:ok, %{
      wip_balance: wip_balance,
      total_debits: debits,
      total_credits: credits,
      orders_in_prep: orders_in_prep
    }}
  end

  defp count_orders_in_prep do
    # Get all orders that have order_in_prep entries
    in_prep_order_ids =
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
      |> MapSet.new()

    # Get all orders that have order_delivered entries
    delivered_order_ids =
      from(je in JournalEntry,
        where: je.entry_type == "order_delivered",
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
      |> MapSet.new()

    # Orders in prep = in_prep - delivered
    MapSet.difference(in_prep_order_ids, delivered_order_ids)
    |> MapSet.size()
  end

  @doc """
  Verifies that inventory cost values match journal entries.
  """
  def verify_inventory_cost_accounting do
    ingredients_account = Accounting.get_account_by_code!(@ingredients_account_code)

    inventory_value = calculate_inventory_value()
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
  Excludes year_end_close entries which are transfer entries that recognize accumulated income.
  """
  def verify_journal_entries_balanced do
    unbalanced_entries =
      from(je in JournalEntry,
        where: je.entry_type != "year_end_close",
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
  Verifies that withdrawal journal entries debit Owner's Drawings (3100) not Owner's Equity (3000).
  """
  def verify_withdrawal_accounts do
    case Repo.get_by(Account, code: @owners_equity_code) do
      nil ->
        {:ok, %{checked: 0, issues: 0}}

      owners_equity ->
        incorrect =
          from(jl in JournalLine,
            join: je in assoc(jl, :journal_entry),
            where: je.entry_type == "withdrawal" and
                   jl.account_id == ^owners_equity.id and
                   jl.debit_cents > 0,
            select: %{
              journal_entry_id: je.id,
              date: je.date,
              reference: je.reference,
              debit_cents: jl.debit_cents
            }
          )
          |> Repo.all()

        if incorrect == [] do
          {:ok, %{checked: "all withdrawals", issues: 0}}
        else
          total_cents = Enum.reduce(incorrect, 0, fn w, acc -> acc + w.debit_cents end)
          {:error, [
            "Found #{length(incorrect)} withdrawal(s) incorrectly debiting Owner's Equity (3000) instead of Owner's Drawings (3100). Total: #{format_currency(total_cents)}"
          ]}
        end
    end
  end

  @doc """
  Verifies that there are no duplicate COGS journal entries (same reference, multiple entries).
  """
  def verify_duplicate_cogs_entries do
    in_prep_dupes =
      from(je in JournalEntry,
        where: je.entry_type == "order_in_prep",
        where: like(je.reference, "Order #%"),
        group_by: je.reference,
        having: count(je.id) > 1,
        select: {je.reference, count(je.id)}
      )
      |> Repo.all()

    delivered_dupes =
      from(je in JournalEntry,
        where: je.entry_type == "order_delivered",
        where: like(je.reference, "Order #%"),
        group_by: je.reference,
        having: count(je.id) > 1,
        select: {je.reference, count(je.id)}
      )
      |> Repo.all()

    total_groups = length(in_prep_dupes) + length(delivered_dupes)

    if total_groups == 0 do
      {:ok, %{checked: "all order entries", duplicate_groups: 0}}
    else
      issues =
        Enum.map(in_prep_dupes, fn {ref, count} ->
          "Duplicate order_in_prep: #{ref} has #{count} entries (expected 1)"
        end) ++
        Enum.map(delivered_dupes, fn {ref, count} ->
          "Duplicate order_delivered: #{ref} has #{count} entries (expected 1)"
        end)

      {:error, issues}
    end
  end

  @doc """
  Verifies that there are no duplicate inventory movements (same ingredient, location,
  type, quantity, date, and source). Duplicates inflate inventory counts and costs.
  """
  def verify_duplicate_movements do
    dupes =
      from(m in InventoryMovement,
        group_by: [m.ingredient_id, m.from_location_id, m.to_location_id, m.movement_type,
                    m.quantity, m.movement_date, m.source_type, m.source_id],
        having: count(m.id) > 1,
        select: %{
          ingredient_id: m.ingredient_id,
          from_location_id: m.from_location_id,
          movement_type: m.movement_type,
          quantity: m.quantity,
          movement_date: m.movement_date,
          source_type: m.source_type,
          source_id: m.source_id,
          count: count(m.id)
        }
      )
      |> Repo.all()

    if dupes == [] do
      {:ok, %{checked: "all movements", duplicate_groups: 0}}
    else
      issues =
        Enum.map(dupes, fn d ->
          ingredient = Repo.get(Ingredient, d.ingredient_id)
          name = if ingredient, do: ingredient.name, else: "ID:#{d.ingredient_id}"
          "Duplicate #{d.movement_type}: #{name} qty=#{d.quantity} on #{d.movement_date} (#{d.count} copies, source: #{d.source_type}/#{d.source_id})"
        end)

      {:error, issues}
    end
  end

  @doc """
  Verifies that delivered gift orders have correct gift accounting (not sale-style).
  Checks both the original order_delivered entry AND any correction entries for the order.
  """
  def verify_gift_order_accounting do
    samples_gifts = Repo.get_by(Account, code: @samples_gifts_code)

    gift_orders =
      from(o in Order,
        where: o.is_gift == true and o.status == "delivered",
        select: o
      )
      |> Repo.all()

    if gift_orders == [] do
      {:ok, %{checked: 0, issues: 0}}
    else
      affected =
        Enum.reduce(gift_orders, [], fn order, acc ->
          reference = "Order ##{order.id}"

          # Look for ANY journal entry for this order that has a 6070 (Samples & Gifts) line.
          # This covers both: orders originally delivered as gifts (order_delivered entry has 6070)
          # and orders corrected later (a separate "other" correction entry has 6070).
          entries =
            from(je in JournalEntry,
              where: je.reference == ^reference,
              select: je
            )
            |> Repo.all()

          case entries do
            [] -> acc
            entries ->
              has_gift_line =
                samples_gifts &&
                Enum.any?(entries, fn entry ->
                  lines =
                    from(jl in JournalLine,
                      where: jl.journal_entry_id == ^entry.id
                    )
                    |> Repo.all()

                  Enum.any?(lines, fn l -> l.account_id == samples_gifts.id end)
                end)

              if has_gift_line do
                acc
              else
                [order.id | acc]
              end
          end
        end)

      if affected == [] do
        {:ok, %{checked: length(gift_orders), issues: 0}}
      else
        {:error, [
          "Found #{length(affected)} delivered gift order(s) with sale-style accounting instead of gift accounting: Order(s) ##{Enum.join(Enum.reverse(affected), ", #")}"
        ]}
      end
    end
  end

  @doc """
  Verifies that no inventory movements have $0 cost when they shouldn't.
  """
  def verify_movement_costs do
    zero_cost_movements =
      from(m in InventoryMovement,
        where: m.movement_type in ["usage", "write_off"],
        where: m.total_cost_cents == 0 or m.unit_cost_cents == 0,
        where: not is_nil(m.from_location_id),
        select: count(m.id)
      )
      |> Repo.one()

    count = case zero_cost_movements do
      nil -> 0
      val when is_integer(val) -> val
      %Decimal{} = val -> Decimal.to_integer(val)
    end

    if count == 0 do
      {:ok, %{checked: "all movements", zero_cost: 0}}
    else
      {:error, [
        "Found #{count} usage/write-off movement(s) with $0 cost that may need backfilling"
      ]}
    end
  end

  @doc """
  Runs all verification checks and returns a report.
  """
  def run_all_checks do
    %{
      inventory_quantities: verify_inventory_quantities(),
      inventory_cost_accounting: verify_inventory_cost_accounting(),
      movement_costs: verify_movement_costs(),
      duplicate_movements: verify_duplicate_movements(),
      wip_balance: verify_wip_balance(),
      order_wip_consistency: verify_order_wip_consistency(),
      journal_entries_balanced: verify_journal_entries_balanced(),
      duplicate_cogs_entries: verify_duplicate_cogs_entries(),
      withdrawal_accounts: verify_withdrawal_accounts(),
      gift_order_accounting: verify_gift_order_accounting()
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

  @doc """
  Repairs inventory cost accounting using a layered approach to minimize P&L impact:
  1. First runs duplicate entry cleanup (P&L-neutral — just removes bad journal entries)
  2. Then, only if a mismatch remains, creates a Waste & Shrinkage (6060) adjustment

  This way, mismatches caused by duplicate order_in_prep entries are fixed without
  any expense hitting the P&L.
  """
  def repair_inventory_cost_accounting do
    ingredients_account = Accounting.get_account_by_code!(@ingredients_account_code)
    waste_account = Accounting.get_account_by_code!(@waste_shrinkage_code)

    # Step 0: Check if there's even a mismatch
    inventory_value = calculate_inventory_value()
    initial_balance = get_account_balance(ingredients_account.id)
    initial_diff = inventory_value - initial_balance

    if abs(initial_diff) < 100 do
      {:ok, []}
    else
      # Step 1: Run duplicate cleanup first (P&L-neutral fix)
      {:ok, dedup_results} = repair_duplicate_cogs_entries()
      dedup_count = length(dedup_results)

      # Step 2: Re-check difference after dedup
      post_dedup_balance = get_account_balance(ingredients_account.id)
      remaining_diff = inventory_value - post_dedup_balance

      step1_report = %{
        step: "1. Duplicate cleanup",
        duplicates_removed: dedup_count,
        initial_difference: format_currency(initial_diff),
        difference_after_cleanup: format_currency(remaining_diff)
      }

      # Step 3: If still mismatched, create shrinkage adjustment
      if abs(remaining_diff) < 100 do
        {:ok, [step1_report | dedup_results]}
      else
        case create_shrinkage_adjustment(ingredients_account, waste_account, inventory_value, post_dedup_balance, remaining_diff) do
          {:ok, adjustment_report} ->
            {:ok, [step1_report | dedup_results] ++ [adjustment_report]}
          {:error, reason} ->
            {:error, reason}
        end
      end
    end
  end

  @doc """
  Repairs duplicate COGS journal entries by keeping the first (lowest ID) and deleting duplicates.
  """
  def repair_duplicate_cogs_entries do
    in_prep_dupes =
      from(je in JournalEntry,
        where: je.entry_type == "order_in_prep",
        where: like(je.reference, "Order #%"),
        group_by: je.reference,
        having: count(je.id) > 1,
        select: {je.reference, count(je.id)}
      )
      |> Repo.all()

    delivered_dupes =
      from(je in JournalEntry,
        where: je.entry_type == "order_delivered",
        where: like(je.reference, "Order #%"),
        group_by: je.reference,
        having: count(je.id) > 1,
        select: {je.reference, count(je.id)}
      )
      |> Repo.all()

    all_dupes = in_prep_dupes ++ delivered_dupes

    if all_dupes == [] do
      {:ok, []}
    else
      results =
        Enum.flat_map(in_prep_dupes, fn {reference, _count} ->
          delete_duplicate_journal_entries(reference, "order_in_prep")
        end) ++
        Enum.flat_map(delivered_dupes, fn {reference, _count} ->
          delete_duplicate_journal_entries(reference, "order_delivered")
        end)

      {:ok, results}
    end
  end

  @doc """
  Repairs withdrawal accounts by creating a correcting entry to move debits
  from Owner's Equity (3000) to Owner's Drawings (3100).
  """
  def repair_withdrawal_accounts do
    owners_equity = Repo.get_by(Account, code: @owners_equity_code)
    owners_drawings = Repo.get_by(Account, code: @owners_drawings_code)

    if is_nil(owners_equity) or is_nil(owners_drawings) do
      {:error, "Required accounts (3000 or 3100) not found"}
    else
      incorrect =
        from(jl in JournalLine,
          join: je in assoc(jl, :journal_entry),
          where: je.entry_type == "withdrawal" and
                 jl.account_id == ^owners_equity.id and
                 jl.debit_cents > 0,
          select: jl.debit_cents
        )
        |> Repo.all()

      if incorrect == [] do
        {:ok, []}
      else
        total_amount = Enum.sum(incorrect)

        entry_attrs = %{
          date: Date.utc_today(),
          entry_type: "other",
          reference: "Withdrawal Account Correction",
          description: "Correct historical withdrawals: move from Owner's Equity (3000) to Owner's Drawings (3100)"
        }

        lines = [
          %{account_id: owners_drawings.id, debit_cents: total_amount, credit_cents: 0,
            description: "Transfer historical withdrawals to Owner's Drawings"},
          %{account_id: owners_equity.id, debit_cents: 0, credit_cents: total_amount,
            description: "Reverse incorrect withdrawal debits from Owner's Equity"}
        ]

        case Accounting.create_journal_entry_with_lines(entry_attrs, lines) do
          {:ok, entry} ->
            {:ok, [%{
              action: "Created correction entry ##{entry.id}",
              amount: format_currency(total_amount),
              details: "Dr Owner's Drawings (3100), Cr Owner's Equity (3000)"
            }]}
          {:error, changeset} ->
            {:error, "Failed to create correction entry: #{inspect(changeset.errors)}"}
        end
      end
    end
  end

  @doc """
  Repairs gift order accounting by creating correction entries for delivered orders
  that were retroactively marked as gifts but still have sale-style accounting.
  """
  def repair_gift_order_accounting do
    wip = Repo.get_by(Account, code: @wip_account_code)
    ar = Repo.get_by(Account, code: @ar_code)
    customer_deposits = Repo.get_by(Account, code: @customer_deposits_code)
    samples_gifts = Repo.get_by(Account, code: @samples_gifts_code)
    gift_contributions = Repo.get_by(Account, code: @gift_contributions_code)

    if Enum.any?([wip, ar, customer_deposits, samples_gifts, gift_contributions], &is_nil/1) do
      {:error, "Required accounts not found. Run migrations first."}
    else
      affected_orders = find_gift_orders_needing_fix(samples_gifts)

      if affected_orders == [] do
        {:ok, []}
      else
        results =
          Enum.map(affected_orders, fn {order, _entry, lines, payment_entries} ->
            apply_gift_correction(order, lines, payment_entries, wip, ar, customer_deposits, samples_gifts, gift_contributions)
          end)

        successes = Enum.filter(results, &match?({:ok, _}, &1)) |> Enum.map(fn {:ok, r} -> r end)
        failures = Enum.filter(results, &match?({:error, _}, &1))

        if failures == [] do
          {:ok, successes}
        else
          {:ok, successes}
        end
      end
    end
  end

  @doc """
  Repairs movement costs by calling Inventory.backfill_movement_costs/0.
  """
  def repair_movement_costs do
    case Inventory.backfill_movement_costs() do
      {:ok, count} ->
        if count > 0 do
          {:ok, [%{action: "Backfilled costs for #{count} movement(s)"}]}
        else
          {:ok, []}
        end
    end
  end

  @doc """
  Repairs duplicate inventory movements by keeping the first (lowest ID) and deleting duplicates.
  Also recalculates inventory quantities after cleanup.
  """
  def repair_duplicate_movements do
    dupes =
      from(m in InventoryMovement,
        group_by: [m.ingredient_id, m.from_location_id, m.to_location_id, m.movement_type,
                    m.quantity, m.movement_date, m.source_type, m.source_id],
        having: count(m.id) > 1,
        select: %{
          ingredient_id: m.ingredient_id,
          from_location_id: m.from_location_id,
          to_location_id: m.to_location_id,
          movement_type: m.movement_type,
          quantity: m.quantity,
          movement_date: m.movement_date,
          source_type: m.source_type,
          source_id: m.source_id
        }
      )
      |> Repo.all()

    if dupes == [] do
      {:ok, []}
    else
      results =
        Enum.flat_map(dupes, fn group ->
          movements =
            from(m in InventoryMovement,
              where: m.ingredient_id == ^group.ingredient_id,
              where: m.movement_type == ^group.movement_type,
              where: m.quantity == ^group.quantity,
              where: m.movement_date == ^group.movement_date,
              where: m.source_type == ^group.source_type,
              where: m.source_id == ^group.source_id,
              order_by: [asc: m.id]
            )
            |> filter_location(group)
            |> Repo.all()

          case movements do
            [_keep | to_delete] when to_delete != [] ->
              Enum.map(to_delete, fn movement ->
                Repo.delete!(movement)
                ingredient = Repo.get(Ingredient, movement.ingredient_id)
                name = if ingredient, do: ingredient.name, else: "ID:#{movement.ingredient_id}"
                %{action: "Deleted duplicate #{movement.movement_type} movement ##{movement.id} for #{name} (qty=#{movement.quantity})"}
              end)
            _ ->
              []
          end
        end)

      # Recalculate inventory quantities after deleting duplicates
      if results != [] do
        repair_inventory_quantities()
      end

      {:ok, results}
    end
  end

  # Helper to filter movements by location (handles nil locations)
  defp filter_location(query, %{from_location_id: nil, to_location_id: nil}) do
    from(m in query, where: is_nil(m.from_location_id) and is_nil(m.to_location_id))
  end
  defp filter_location(query, %{from_location_id: from_id, to_location_id: nil}) do
    from(m in query, where: m.from_location_id == ^from_id and is_nil(m.to_location_id))
  end
  defp filter_location(query, %{from_location_id: nil, to_location_id: to_id}) do
    from(m in query, where: is_nil(m.from_location_id) and m.to_location_id == ^to_id)
  end
  defp filter_location(query, %{from_location_id: from_id, to_location_id: to_id}) do
    from(m in query, where: m.from_location_id == ^from_id and m.to_location_id == ^to_id)
  end

  @doc """
  Dispatcher function for running repairs by type string.
  """
  def run_repair(repair_type) do
    case repair_type do
      "inventory_quantities" -> repair_inventory_quantities()
      "inventory_cost_accounting" -> repair_inventory_cost_accounting()
      "duplicate_cogs_entries" -> repair_duplicate_cogs_entries()
      "duplicate_movements" -> repair_duplicate_movements()
      "withdrawal_accounts" -> repair_withdrawal_accounts()
      "gift_order_accounting" -> repair_gift_order_accounting()
      "movement_costs" -> repair_movement_costs()
      _ -> {:error, "Unknown repair type: #{repair_type}"}
    end
  end

  # Map of checks that have corresponding repair functions
  @repairable_checks MapSet.new([
    :inventory_quantities,
    :inventory_cost_accounting,
    :duplicate_cogs_entries,
    :duplicate_movements,
    :withdrawal_accounts,
    :gift_order_accounting,
    :movement_costs
  ])

  def repairable?(check_name), do: MapSet.member?(@repairable_checks, check_name)

  # ── Private helpers for gift order repair ───────────────────────────────

  defp find_gift_orders_needing_fix(samples_gifts) do
    gift_orders =
      from(o in Order,
        where: o.is_gift == true and o.status == "delivered",
        select: o
      )
      |> Repo.all()

    Enum.reduce(gift_orders, [], fn order, acc ->
      reference = "Order ##{order.id}"

      # Check ALL entries for this order (delivered + any corrections)
      all_entries =
        from(je in JournalEntry,
          where: je.reference == ^reference
        )
        |> Repo.all()

      # Find the original order_delivered entry (needed for the repair)
      delivered_entry = Enum.find(all_entries, fn e -> e.entry_type == "order_delivered" end)

      case delivered_entry do
        nil -> acc
        entry ->
          # Check if ANY entry for this order already has a 6070 line
          has_gift_line =
            Enum.any?(all_entries, fn e ->
              from(jl in JournalLine,
                where: jl.journal_entry_id == ^e.id and jl.account_id == ^samples_gifts.id,
                select: count(jl.id)
              )
              |> Repo.one()
              |> Kernel.>(0)
            end)

          if has_gift_line do
            acc
          else
            lines =
              from(jl in JournalLine,
                where: jl.journal_entry_id == ^entry.id,
                preload: [:account]
              )
              |> Repo.all()

            payment_entries = find_order_payment_entries(order.id)
            [{order, entry, lines, payment_entries} | acc]
          end
      end
    end)
    |> Enum.reverse()
  end

  defp find_order_payment_entries(order_id) do
    reference_prefix = "Order ##{order_id} payment #%"

    entries =
      from(je in JournalEntry,
        where: je.entry_type == "order_payment" and like(je.reference, ^reference_prefix)
      )
      |> Repo.all()

    Enum.map(entries, fn entry ->
      lines =
        from(jl in JournalLine,
          where: jl.journal_entry_id == ^entry.id,
          preload: [:account]
        )
        |> Repo.all()

      {entry, lines}
    end)
  end

  defp apply_gift_correction(order, original_lines, payment_entries, wip, ar, customer_deposits, samples_gifts, gift_contributions) do
    # Reverse all original delivery lines
    reversal_lines =
      Enum.map(original_lines, fn line ->
        %{
          account_id: line.account_id,
          debit_cents: line.credit_cents,
          credit_cents: line.debit_cents,
          description: "Reversal: #{line.description || "line for order ##{order.id}"}"
        }
      end)

    # Find WIP credit amount (production cost)
    cost_cents =
      Enum.reduce(original_lines, 0, fn line, acc ->
        if line.account_id == wip.id and line.credit_cents > 0 do
          acc + line.credit_cents
        else
          acc
        end
      end)

    # Gift expense lines
    gift_lines =
      if cost_cents > 0 do
        [
          %{account_id: samples_gifts.id, debit_cents: cost_cents, credit_cents: 0,
            description: "Samples & Gifts expense for gift order ##{order.id}"},
          %{account_id: wip.id, debit_cents: 0, credit_cents: cost_cents,
            description: "Relieve WIP for gift order ##{order.id}"}
        ]
      else
        []
      end

    # Payment reclassification lines
    payment_reclassification_lines =
      Enum.flat_map(payment_entries, fn {_pentry, plines} ->
        Enum.flat_map(plines, fn line ->
          cond do
            line.account_id == ar.id and line.credit_cents > 0 ->
              [
                %{account_id: ar.id, debit_cents: line.credit_cents, credit_cents: 0,
                  description: "Reverse AR credit from payment for gift order ##{order.id}"},
                %{account_id: gift_contributions.id, debit_cents: 0, credit_cents: line.credit_cents,
                  description: "Reclassify payment as gift contribution for order ##{order.id}"}
              ]
            line.account_id == customer_deposits.id and line.credit_cents > 0 ->
              [
                %{account_id: customer_deposits.id, debit_cents: line.credit_cents, credit_cents: 0,
                  description: "Reverse deposit credit from payment for gift order ##{order.id}"},
                %{account_id: gift_contributions.id, debit_cents: 0, credit_cents: line.credit_cents,
                  description: "Reclassify deposit as gift contribution for order ##{order.id}"}
              ]
            true -> []
          end
        end)
      end)

    all_lines = reversal_lines ++ gift_lines ++ payment_reclassification_lines

    entry_attrs = %{
      date: Date.utc_today(),
      entry_type: "other",
      reference: "Order ##{order.id}",
      description: "Correct order ##{order.id}: convert sale accounting to gift/sample"
    }

    case Accounting.create_journal_entry_with_lines(entry_attrs, all_lines) do
      {:ok, entry} ->
        {:ok, %{action: "Order ##{order.id} — correction entry ##{entry.id} created"}}
      {:error, changeset} ->
        {:error, "Order ##{order.id} — failed: #{inspect(changeset.errors)}"}
    end
  end

  # ── Private helper for duplicate COGS repair ────────────────────────────

  defp delete_duplicate_journal_entries(reference, entry_type) do
    entries =
      from(je in JournalEntry,
        where: je.reference == ^reference and je.entry_type == ^entry_type,
        order_by: [asc: je.id],
        select: je
      )
      |> Repo.all()

    case entries do
      [_keep | to_delete] when to_delete != [] ->
        Enum.map(to_delete, fn entry ->
          Repo.delete!(entry)
          %{action: "Deleted duplicate #{entry_type} entry ##{entry.id} for #{reference}"}
        end)
      _ ->
        []
    end
  end

  # ── Shared helper functions ─────────────────────────────────────────────

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

  # Calculates the total inventory value from InventoryItem records (qty × avg_cost)
  defp calculate_inventory_value do
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
  end

  # Creates a shrinkage adjustment journal entry to reconcile the remaining mismatch
  defp create_shrinkage_adjustment(ingredients_account, waste_account, inventory_value, account_balance, diff) do
    lines =
      if diff > 0 do
        # Inventory worth more than accounting shows: Dr Inventory, Cr Waste & Shrinkage
        [
          %{account_id: ingredients_account.id, debit_cents: diff, credit_cents: 0,
            description: "Adjust Ingredients Inventory to match actual value"},
          %{account_id: waste_account.id, debit_cents: 0, credit_cents: diff,
            description: "Offset inventory adjustment (waste & shrinkage reversal)"}
        ]
      else
        # Inventory worth less: Dr Waste & Shrinkage, Cr Inventory
        abs_diff = abs(diff)
        [
          %{account_id: waste_account.id, debit_cents: abs_diff, credit_cents: 0,
            description: "Inventory shrinkage/waste adjustment"},
          %{account_id: ingredients_account.id, debit_cents: 0, credit_cents: abs_diff,
            description: "Adjust Ingredients Inventory to match actual value"}
        ]
      end

    entry_attrs = %{
      date: Date.utc_today(),
      entry_type: "other",
      reference: "Inventory Cost Adjustment",
      description: "Adjust account 1200 balance to match inventory value (diff: #{format_currency(diff)})"
    }

    case Accounting.create_journal_entry_with_lines(entry_attrs, lines) do
      {:ok, entry} ->
        {:ok, %{
          step: "2. Shrinkage adjustment",
          action: "Created adjusting entry ##{entry.id}",
          inventory_value: format_currency(inventory_value),
          account_balance: format_currency(account_balance),
          adjustment: format_currency(diff)
        }}
      {:error, changeset} ->
        {:error, "Failed to create adjusting entry: #{inspect(changeset.errors)}"}
    end
  end

  # Helper function to format cents as currency
  defp format_currency(cents) when is_integer(cents) do
    abs_cents = abs(cents)
    pesos = div(abs_cents, 100)
    cents_remainder = rem(abs_cents, 100)
    sign = if cents < 0, do: "-", else: ""
    "#{sign}#{pesos}.#{String.pad_leading(Integer.to_string(cents_remainder), 2, "0")} MXN"
  end
end
