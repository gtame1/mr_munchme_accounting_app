defmodule Ledgr.Repo.Migrations.FixHistoricalAccountingErrors do
  use Ecto.Migration
  import Ecto.Query

  @ar_code "1100"
  @wip_code "1220"
  @customer_deposits_code "2200"
  @owners_equity_code "3000"
  @owners_drawings_code "3100"
  @sales_code "4000"
  @gift_contributions_code "4100"
  @samples_gifts_code "6070"
  @shipping_product_sku "ENVIO"

  # ──────────────────────────────────────────────────────────────────────────
  # This migration permanently fixes five categories of historical accounting
  # bugs. All fixes are idempotent — running the migration twice is safe.
  #
  #   Fix 1: Withdrawal journal lines debited Owner's Equity (3000) instead
  #           of Owner's Drawings (3100). Update in place.
  #
  #   Fix 2: Duplicate order_in_prep / order_delivered journal entries for the
  #           same order. Keep the lowest-ID entry, delete the rest.
  #
  #   Fix 3: Duplicate inventory movements for the same order. Keep the
  #           lowest-ID movement, delete the rest.
  #
  #   Fix 3b: Recalculate inventories.quantity_on_hand from movements (covers
  #            any drift caused by duplicate movements or direct DB edits).
  #
  #   Fix 4: Gift orders that went through sale-style delivery accounting.
  #           Create a correction entry: reverse the delivery lines, add gift
  #           expense lines, and reclassify payment entries.
  #
  #   Fix 5: Delivered orders where Customer Deposits (2200) still carry a
  #           positive balance. Create the missing Dr 2200 / Cr AR transfer.
  #           MUST run before Fix 6.
  #
  #   Fix 6: Delivered non-gift orders where GL AR doesn't match expected AR
  #           (expected = order total – total paid). Create a correction entry.
  # ──────────────────────────────────────────────────────────────────────────

  def up do
    fix_withdrawal_accounts()
    fix_duplicate_cogs_entries()
    fix_duplicate_movements()
    recalculate_inventory_quantities()
    fix_gift_order_accounting()
    fix_customer_deposits()    # must run before fix_ar_balance
    fix_ar_balance()
    :ok
  end

  def down do
    # These are data corrections, not schema changes — not safely reversible.
    :ok
  end

  # ── Fix 1: Withdrawal accounts 3000 → 3100 ─────────────────────────────

  defp fix_withdrawal_accounts do
    execute """
    UPDATE journal_lines
    SET account_id = (SELECT id FROM accounts WHERE code = '#{@owners_drawings_code}')
    WHERE account_id = (SELECT id FROM accounts WHERE code = '#{@owners_equity_code}')
      AND debit_cents > 0
      AND journal_entry_id IN (
        SELECT id FROM journal_entries WHERE entry_type = 'withdrawal'
      )
      AND EXISTS (SELECT 1 FROM accounts WHERE code = '#{@owners_drawings_code}')
    """

    # Remove stale "Withdrawal Account Correction" entries created by the old
    # repair function (they're redundant now that the lines are corrected).
    execute """
    DELETE FROM journal_lines
    WHERE journal_entry_id IN (
      SELECT id FROM journal_entries
      WHERE reference = 'Withdrawal Account Correction'
    )
    """

    execute """
    DELETE FROM journal_entries
    WHERE reference = 'Withdrawal Account Correction'
    """
  end

  # ── Fix 2: Duplicate COGS journal entries ──────────────────────────────

  defp fix_duplicate_cogs_entries do
    # Delete lines first (FK constraint), then the duplicate entries.
    # "Keep lowest ID" means: for each (entry_type, reference) pair, keep MIN(id).
    execute """
    DELETE FROM journal_lines
    WHERE journal_entry_id IN (
      SELECT je.id FROM journal_entries je
      WHERE je.entry_type IN ('order_in_prep', 'order_delivered')
        AND je.reference LIKE 'Order #%'
        AND je.id NOT IN (
          SELECT MIN(je2.id)
          FROM journal_entries je2
          WHERE je2.entry_type = je.entry_type
            AND je2.reference = je.reference
          GROUP BY je2.entry_type, je2.reference
        )
    )
    """

    execute """
    DELETE FROM journal_entries
    WHERE entry_type IN ('order_in_prep', 'order_delivered')
      AND reference LIKE 'Order #%'
      AND id NOT IN (
        SELECT MIN(je2.id)
        FROM journal_entries je2
        WHERE je2.entry_type IN ('order_in_prep', 'order_delivered')
          AND je2.reference LIKE 'Order #%'
        GROUP BY je2.entry_type, je2.reference
      )
    """
  end

  # ── Fix 3: Duplicate inventory movements ───────────────────────────────

  defp fix_duplicate_movements do
    # COALESCE location IDs to a sentinel string so NULL != NULL doesn't
    # prevent grouping of movements that have no from/to location.
    execute """
    DELETE FROM inventory_movements
    WHERE id IN (
      SELECT id FROM (
        SELECT id,
               ROW_NUMBER() OVER (
                 PARTITION BY
                   ingredient_id,
                   COALESCE(from_location_id::text, '__null__'),
                   COALESCE(to_location_id::text, '__null__'),
                   movement_type,
                   quantity,
                   source_type,
                   source_id
                 ORDER BY id ASC
               ) AS rn
        FROM inventory_movements
      ) ranked
      WHERE rn > 1
    )
    """
  end

  # ── Fix 3b: Recalculate inventories.quantity_on_hand ───────────────────

  defp recalculate_inventory_quantities do
    execute """
    UPDATE inventories
    SET quantity_on_hand = (
      SELECT
        COALESCE(SUM(
          CASE
            WHEN im.to_location_id = inventories.location_id
                 AND im.movement_type IN ('purchase', 'transfer')
            THEN im.quantity
            ELSE 0
          END
        ), 0)
        -
        COALESCE(SUM(
          CASE
            WHEN im.from_location_id = inventories.location_id
                 AND im.movement_type IN ('usage', 'write_off', 'transfer')
            THEN im.quantity
            ELSE 0
          END
        ), 0)
      FROM inventory_movements im
      WHERE im.ingredient_id = inventories.ingredient_id
        AND (
          (im.to_location_id = inventories.location_id AND im.movement_type IN ('purchase', 'transfer'))
          OR
          (im.from_location_id = inventories.location_id AND im.movement_type IN ('usage', 'write_off', 'transfer'))
        )
    )
    """
  end

  # ── Fix 4: Gift order accounting ────────────────────────────────────────

  defp fix_gift_order_accounting do
    accounts = get_accounts([@wip_code, @ar_code, @customer_deposits_code, @samples_gifts_code, @gift_contributions_code])

    wip_id = accounts[@wip_code]
    ar_id = accounts[@ar_code]
    deposits_id = accounts[@customer_deposits_code]
    gifts_id = accounts[@samples_gifts_code]
    contributions_id = accounts[@gift_contributions_code]

    if is_nil(wip_id) or is_nil(ar_id) or is_nil(deposits_id) or is_nil(gifts_id) or is_nil(contributions_id) do
      :ok
    else
      gift_orders = Ledgr.Repo.all(
        from o in "orders",
        where: o.is_gift == true and o.status == "delivered",
        select: %{id: o.id}
      )

      Enum.each(gift_orders, fn %{id: order_id} ->
        reference = "Order ##{order_id}"

        # Check if ANY entry for this order already has a gifts/samples line.
        # If so, this order was already corrected — skip it.
        entry_ids = Ledgr.Repo.all(
          from je in "journal_entries",
          where: je.reference == ^reference,
          select: je.id
        )

        has_gift_line =
          entry_ids != [] and
            Ledgr.Repo.one(
              from jl in "journal_lines",
              where: jl.journal_entry_id in ^entry_ids and jl.account_id == ^gifts_id,
              select: count(jl.id)
            ) > 0

        unless has_gift_line do
          delivered_entry = Ledgr.Repo.one(
            from je in "journal_entries",
            where: je.reference == ^reference and je.entry_type == "order_delivered",
            select: %{id: je.id},
            limit: 1
          )

          if delivered_entry do
            delivery_lines = Ledgr.Repo.all(
              from jl in "journal_lines",
              where: jl.journal_entry_id == ^delivered_entry.id,
              select: %{
                account_id: jl.account_id,
                debit_cents: jl.debit_cents,
                credit_cents: jl.credit_cents,
                description: jl.description
              }
            )

            cost_cents = Enum.reduce(delivery_lines, 0, fn line, acc ->
              if line.account_id == wip_id and line.credit_cents > 0,
                do: acc + line.credit_cents,
                else: acc
            end)

            payment_entry_ids = Ledgr.Repo.all(
              from je in "journal_entries",
              where: je.entry_type == "order_payment" and like(je.reference, ^"Order ##{order_id} payment #%"),
              select: je.id
            )

            payment_lines =
              if payment_entry_ids == [] do
                []
              else
                Ledgr.Repo.all(
                  from jl in "journal_lines",
                  where: jl.journal_entry_id in ^payment_entry_ids,
                  select: %{
                    account_id: jl.account_id,
                    debit_cents: jl.debit_cents,
                    credit_cents: jl.credit_cents
                  }
                )
              end

            reversal_lines = Enum.map(delivery_lines, fn line ->
              %{
                account_id: line.account_id,
                debit_cents: line.credit_cents,
                credit_cents: line.debit_cents,
                description: "Reversal: #{line.description || "delivery line for order ##{order_id}"}"
              }
            end)

            gift_expense_lines =
              if cost_cents > 0 do
                [
                  %{account_id: gifts_id, debit_cents: cost_cents, credit_cents: 0,
                    description: "Samples & Gifts expense for gift order ##{order_id}"},
                  %{account_id: wip_id, debit_cents: 0, credit_cents: cost_cents,
                    description: "Relieve WIP for gift order ##{order_id}"}
                ]
              else
                []
              end

            reclassification_lines = Enum.flat_map(payment_lines, fn line ->
              cond do
                line.account_id == ar_id and line.credit_cents > 0 ->
                  [
                    %{account_id: ar_id, debit_cents: line.credit_cents, credit_cents: 0,
                      description: "Reverse AR credit from payment for gift order ##{order_id}"},
                    %{account_id: contributions_id, debit_cents: 0, credit_cents: line.credit_cents,
                      description: "Reclassify payment as gift contribution for order ##{order_id}"}
                  ]
                line.account_id == deposits_id and line.credit_cents > 0 ->
                  [
                    %{account_id: deposits_id, debit_cents: line.credit_cents, credit_cents: 0,
                      description: "Reverse deposit credit from payment for gift order ##{order_id}"},
                    %{account_id: contributions_id, debit_cents: 0, credit_cents: line.credit_cents,
                      description: "Reclassify deposit as gift contribution for order ##{order_id}"}
                  ]
                true ->
                  []
              end
            end)

            all_lines = reversal_lines ++ gift_expense_lines ++ reclassification_lines

            if all_lines != [] do
              now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

              {1, [correction_entry]} = Ledgr.Repo.insert_all(
                "journal_entries",
                [%{
                  date: Date.utc_today(),
                  entry_type: "other",
                  reference: reference,
                  description: "Correct order ##{order_id}: convert sale accounting to gift/sample",
                  inserted_at: now,
                  updated_at: now
                }],
                returning: [:id]
              )

              lines_with_meta = Enum.map(all_lines, fn line ->
                Map.merge(line, %{
                  journal_entry_id: correction_entry.id,
                  inserted_at: now,
                  updated_at: now
                })
              end)

              Ledgr.Repo.insert_all("journal_lines", lines_with_meta)
            end
          end
        end
      end)
    end
  end

  # ── Fix 5: Customer deposit transfers ──────────────────────────────────

  defp fix_customer_deposits do
    accounts = get_accounts([@ar_code, @customer_deposits_code])
    ar_id = accounts[@ar_code]
    deposits_id = accounts[@customer_deposits_code]

    if is_nil(ar_id) or is_nil(deposits_id) do
      :ok
    else
      gl_deposits_by_order = get_gl_liability_balance_by_order(deposits_id)

      delivered_order_ids = Ledgr.Repo.all(
        from o in "orders",
        where: o.status == "delivered",
        select: o.id
      )

      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      Enum.each(delivered_order_ids, fn order_id ->
        gl_deposits = Map.get(gl_deposits_by_order, order_id, 0)

        if gl_deposits > 0 do
          {1, [entry]} = Ledgr.Repo.insert_all(
            "journal_entries",
            [%{
              date: Date.utc_today(),
              entry_type: "other",
              reference: "Order ##{order_id} deposit transfer",
              description: "Transfer stale customer deposits for delivered order ##{order_id}",
              inserted_at: now,
              updated_at: now
            }],
            returning: [:id]
          )

          Ledgr.Repo.insert_all("journal_lines", [
            %{
              journal_entry_id: entry.id,
              account_id: deposits_id,
              debit_cents: gl_deposits,
              credit_cents: 0,
              description: "Transfer stale deposits for delivered order ##{order_id}",
              inserted_at: now,
              updated_at: now
            },
            %{
              journal_entry_id: entry.id,
              account_id: ar_id,
              debit_cents: 0,
              credit_cents: gl_deposits,
              description: "Reduce AR by transferred deposits for order ##{order_id}",
              inserted_at: now,
              updated_at: now
            }
          ])
        end
      end)
    end
  end

  # ── Fix 6: AR balance corrections ──────────────────────────────────────

  defp fix_ar_balance do
    accounts = get_accounts([@ar_code, @sales_code])
    ar_id = accounts[@ar_code]
    sales_id = accounts[@sales_code]

    if is_nil(ar_id) or is_nil(sales_id) do
      :ok
    else
      shipping_fallback = Ledgr.Repo.one(
        from p in "products",
        where: p.sku == @shipping_product_sku,
        select: p.price_cents,
        limit: 1
      ) || 0

      orders = Ledgr.Repo.all(
        from o in "orders",
        join: p in "products", on: p.id == o.product_id,
        where: o.status == "delivered" and o.is_gift == false,
        select: %{
          id: o.id,
          price_cents: p.price_cents,
          quantity: o.quantity,
          discount_type: o.discount_type,
          discount_value: o.discount_value,
          customer_paid_shipping: o.customer_paid_shipping,
          shipping_fee_cents: o.shipping_fee_cents
        }
      )

      payments_by_order =
        Ledgr.Repo.all(
          from p in "order_payments",
          group_by: p.order_id,
          select: {
            p.order_id,
            fragment("SUM(COALESCE(?, ?))", p.customer_amount_cents, p.amount_cents)
          }
        )
        |> Map.new()

      gl_ar_by_order = get_gl_balance_by_order(ar_id)

      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      Enum.each(orders, fn order ->
        order_total = compute_order_total(order, shipping_fallback)
        total_paid = to_int(Map.get(payments_by_order, order.id, 0))
        expected_ar = max(order_total - total_paid, 0)
        gl_ar = Map.get(gl_ar_by_order, order.id, 0)
        diff = expected_ar - gl_ar

        if diff != 0 do
          abs_diff = abs(diff)

          {1, [entry]} = Ledgr.Repo.insert_all(
            "journal_entries",
            [%{
              date: Date.utc_today(),
              entry_type: "other",
              reference: "Order ##{order.id} AR correction",
              description: "AR balance correction for order ##{order.id}",
              inserted_at: now,
              updated_at: now
            }],
            returning: [:id]
          )

          lines =
            if diff > 0 do
              # GL AR too low — debit AR, credit Sales
              [
                %{journal_entry_id: entry.id, account_id: ar_id,
                  debit_cents: abs_diff, credit_cents: 0,
                  description: "AR correction: increase AR for order ##{order.id}",
                  inserted_at: now, updated_at: now},
                %{journal_entry_id: entry.id, account_id: sales_id,
                  debit_cents: 0, credit_cents: abs_diff,
                  description: "AR correction offset for order ##{order.id}",
                  inserted_at: now, updated_at: now}
              ]
            else
              # GL AR too high — debit Sales, credit AR
              [
                %{journal_entry_id: entry.id, account_id: sales_id,
                  debit_cents: abs_diff, credit_cents: 0,
                  description: "AR correction: reverse excess AR for order ##{order.id}",
                  inserted_at: now, updated_at: now},
                %{journal_entry_id: entry.id, account_id: ar_id,
                  debit_cents: 0, credit_cents: abs_diff,
                  description: "AR correction: reduce AR for order ##{order.id}",
                  inserted_at: now, updated_at: now}
              ]
            end

          Ledgr.Repo.insert_all("journal_lines", lines)
        end
      end)
    end
  end

  # ── Private helpers ──────────────────────────────────────────────────────

  defp get_accounts(codes) do
    Ledgr.Repo.all(
      from a in "accounts",
      where: a.code in ^codes,
      select: {a.code, a.id}
    )
    |> Map.new()
  end

  # Returns %{order_id => balance} where balance = debits – credits (asset account).
  # Aggregates across ALL journal entries referencing "Order #N".
  defp get_gl_balance_by_order(account_id) do
    Ledgr.Repo.all(
      from jl in "journal_lines",
      join: je in "journal_entries", on: jl.journal_entry_id == je.id,
      where: jl.account_id == ^account_id,
      where: like(je.reference, "Order #%"),
      group_by: je.reference,
      select: {
        je.reference,
        fragment("SUM(?)", jl.debit_cents),
        fragment("SUM(?)", jl.credit_cents)
      }
    )
    |> Enum.reduce(%{}, fn {reference, debits, credits}, acc ->
      case Regex.run(~r/Order #(\d+)/, reference) do
        [_, id_str] ->
          order_id = String.to_integer(id_str)
          balance = to_int(debits) - to_int(credits)
          Map.update(acc, order_id, balance, &(&1 + balance))
        _ ->
          acc
      end
    end)
  end

  # Returns %{order_id => balance} where balance = credits – debits (liability account).
  defp get_gl_liability_balance_by_order(account_id) do
    Ledgr.Repo.all(
      from jl in "journal_lines",
      join: je in "journal_entries", on: jl.journal_entry_id == je.id,
      where: jl.account_id == ^account_id,
      where: like(je.reference, "Order #%"),
      group_by: je.reference,
      select: {
        je.reference,
        fragment("SUM(?)", jl.debit_cents),
        fragment("SUM(?)", jl.credit_cents)
      }
    )
    |> Enum.reduce(%{}, fn {reference, debits, credits}, acc ->
      case Regex.run(~r/Order #(\d+)/, reference) do
        [_, id_str] ->
          order_id = String.to_integer(id_str)
          balance = to_int(credits) - to_int(debits)
          Map.update(acc, order_id, balance, &(&1 + balance))
        _ ->
          acc
      end
    end)
  end

  defp compute_order_total(order, shipping_fallback) do
    base = (order.price_cents || 0) * (order.quantity || 1)

    discount_cents =
      case {order.discount_type, order.discount_value} do
        {"flat", v} when not is_nil(v) ->
          v
          |> Decimal.mult(Decimal.new(100))
          |> Decimal.round(0)
          |> Decimal.to_integer()

        {"percentage", v} when not is_nil(v) ->
          base
          |> Decimal.new()
          |> Decimal.mult(v)
          |> Decimal.div(Decimal.new(100))
          |> Decimal.round(0)
          |> Decimal.to_integer()

        _ ->
          0
      end

    discounted = max(base - discount_cents, 0)

    shipping =
      if order.customer_paid_shipping do
        order.shipping_fee_cents || shipping_fallback
      else
        0
      end

    discounted + shipping
  end

  defp to_int(nil), do: 0
  defp to_int(n) when is_integer(n), do: n
  defp to_int(%Decimal{} = d), do: Decimal.to_integer(d)
  defp to_int(n) when is_float(n), do: round(n)
end
