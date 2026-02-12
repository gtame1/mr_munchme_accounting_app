defmodule Ledgr.Domains.MrMunchMe.OrderAccounting do
  @moduledoc """
  MrMunchMe-specific accounting logic for orders, payments, and product
  revenue/COGS breakdowns.

  This module was extracted from `Ledgr.Core.Accounting` to keep the core
  context free of domain-specific imports.  It delegates to Core for generic
  accounting operations (create/update journal entries, get accounts, etc.).
  """

  import Ecto.Query, warn: false

  alias Ledgr.Repo
  alias Ledgr.Domains.MrMunchMe.Orders.{Order, OrderPayment, Product}
  alias Ledgr.Domains.MrMunchMe.Inventory
  alias Ledgr.Core.Accounting
  alias Ledgr.Core.Accounting.{JournalEntry, JournalLine}

  # ── MrMunchMe-specific account codes ──────────────────────────────────
  @ar_code "1100"
  @ingredients_inventory_code "1200"
  @packing_inventory_code "1210"
  @wip_inventory_code "1220"
  @kitchen_inventory_code "1300"
  @customer_deposits_code "2200"
  @sales_code "4000"
  @sales_discounts_code "4010"
  @ingredients_cogs_code "5000"
  @packing_cogs_code "5010"
  @samples_gifts_code "6070"

  @shipping_product_sku "ENVIO"

  # ── Order status change dispatcher ────────────────────────────────────

  def handle_order_status_change(%Order{} = order, new_status) do
    case new_status do
      "in_prep" ->
        cost_breakdown = Inventory.consume_for_order(order)
        record_order_in_prep(order, cost_breakdown)
      "delivered" -> record_order_delivered(order)
      "new_order" -> record_order_created(order)
      "canceled" -> record_order_canceled(order)
      _ ->
        :ok
    end
  end

  # Order creation is not an accounting event (no cash, no delivery yet),
  # so for now this is a no-op.
  def record_order_created(%Order{} = _order), do: :ok

  @doc """
  When an order moves to in_prep, move the ingredient cost into WIP:

    Dr WIP Inventory (1220)
    Cr Ingredients Inventory (1200)  — for ingredient costs
    Cr Packing Inventory (1210)      — for packing costs
    Cr Kitchen Equipment (1300)      — for kitchen costs

  `cost_breakdown` is a map: %{ingredients: cents, packing: cents, kitchen: cents, total: cents}
  """
  def record_order_in_prep(%Order{} = order, cost_breakdown) do
    reference = "Order ##{order.id}"

    # Check if already recorded to prevent duplicates
    existing =
      from(je in JournalEntry,
        where: je.entry_type == "order_in_prep" and je.reference == ^reference
      )
      |> Repo.one()

    if existing do
      {:ok, existing}
    else
      total_cost_cents = cost_breakdown.total

      wip = Accounting.get_account_by_code!(@wip_inventory_code)

      entry_attrs = %{
        date: order.delivery_date || Date.utc_today(),
        entry_type: "order_in_prep",
        reference: reference,
        description: "Move ingredients to WIP for order ##{order.id}"
      }

      # Debit WIP with total cost
      debit_line = %{
        account_id: wip.id,
        debit_cents: total_cost_cents,
        credit_cents: 0,
        description: "WIP for order ##{order.id}"
      }

      # Credit each inventory account for its portion
      account_map = [
        {cost_breakdown.ingredients, @ingredients_inventory_code, "Ingredients"},
        {cost_breakdown.packing, @packing_inventory_code, "Packing"},
        {cost_breakdown.kitchen, @kitchen_inventory_code, "Kitchen"}
      ]

      credit_lines =
        account_map
        |> Enum.filter(fn {cents, _code, _label} -> cents > 0 end)
        |> Enum.map(fn {cents, account_code, label} ->
          account = Accounting.get_account_by_code!(account_code)
          %{
            account_id: account.id,
            debit_cents: 0,
            credit_cents: cents,
            description: "#{label} used for order ##{order.id}"
          }
        end)

      Accounting.create_journal_entry_with_lines(entry_attrs, [debit_line | credit_lines])
    end
  end

  def record_order_delivered(%Order{} = order) do
    reference = "Order ##{order.id}"

    # Check if already recorded to prevent duplicates
    existing =
      from(je in JournalEntry,
        where: je.entry_type == "order_delivered" and je.reference == ^reference
      )
      |> Repo.one()

    if existing do
      {:ok, existing}
    else
      do_record_order_delivered(order, reference)
    end
  end

  @doc """
  When an in-prep order is canceled, reverse the WIP journal entry and restore inventory.
  If the order was never in-prep, this is a no-op.
  """
  def record_order_canceled(%Order{} = order) do
    reference = "Order ##{order.id}"

    # Check if there was an "order_in_prep" journal entry to reverse
    in_prep_entry =
      from(je in JournalEntry,
        where: je.entry_type == "order_in_prep" and je.reference == ^reference,
        preload: [:journal_lines]
      )
      |> Repo.one()

    # Also check that we haven't already reversed (or delivered) this order
    already_reversed =
      from(je in JournalEntry,
        where: je.entry_type == "order_canceled" and je.reference == ^reference
      )
      |> Repo.one()

    already_delivered =
      from(je in JournalEntry,
        where: je.entry_type == "order_delivered" and je.reference == ^reference
      )
      |> Repo.one()

    cond do
      is_nil(in_prep_entry) ->
        # Never went to in_prep, nothing to reverse
        :ok

      already_reversed ->
        # Already reversed, idempotent
        {:ok, already_reversed}

      already_delivered ->
        # Already delivered, cannot cancel accounting (order should not reach here)
        :ok

      true ->
        # Reverse the WIP journal entry: swap debits and credits
        reversal_lines =
          Enum.map(in_prep_entry.journal_lines, fn line ->
            %{
              account_id: line.account_id,
              debit_cents: line.credit_cents,
              credit_cents: line.debit_cents,
              description: "Reversal: #{line.description}"
            }
          end)

        entry_attrs = %{
          date: Date.utc_today(),
          entry_type: "order_canceled",
          reference: reference,
          description: "Reverse WIP for canceled order ##{order.id}"
        }

        # Reverse inventory movements (restore stock)
        Inventory.reverse_order_consumption(order.id)

        Accounting.create_journal_entry_with_lines(entry_attrs, reversal_lines)
    end
  end

  def record_order_payment(%OrderPayment{} = payment) do
    payment = Repo.preload(payment, [:order, :paid_to_account, :partner, :partner_payable_account])

    order = payment.order
    paid_to = payment.paid_to_account

    # Calculate amounts: default customer_amount to total if not set
    total_amount = payment.amount_cents
    customer_amount = payment.customer_amount_cents || total_amount
    partner_amount = payment.partner_amount_cents || 0

    entry_attrs = %{
      date: payment.payment_date,
      entry_type: "order_payment",
      reference: "Order ##{order.id} payment ##{payment.id}",
      description: "Payment from #{order.customer_name}"
    }

    # Build journal entry lines
    lines = build_payment_journal_lines(
      paid_to,
      order,
      payment,
      total_amount,
      customer_amount,
      partner_amount
    )

    Accounting.create_journal_entry_with_lines(entry_attrs, lines)
  end

  def update_order_payment_journal_entry(%OrderPayment{} = payment) do
    payment =
      payment
      |> Repo.reload()
      |> Repo.preload([:order, :paid_to_account, :partner, :partner_payable_account])

    reference = "Order ##{payment.order_id} payment ##{payment.id}"

    journal_entry =
      from(je in JournalEntry, where: je.reference == ^reference)
      |> Repo.one()

    if journal_entry do
      order = payment.order
      paid_to = payment.paid_to_account

      # Ensure paid_to_account is loaded
      if is_nil(paid_to) do
        {:error, "Paid to account is missing for payment"}
      else
        # Calculate amounts: default customer_amount to total if not set
        total_amount = payment.amount_cents
        customer_amount = payment.customer_amount_cents || total_amount
        partner_amount = payment.partner_amount_cents || 0

        entry_attrs = %{
          date: payment.payment_date,
          description: "Payment from #{order.customer_name}"
        }

        # Build journal entry lines
        lines = build_payment_journal_lines(
          paid_to,
          order,
          payment,
          total_amount,
          customer_amount,
          partner_amount
        )

        Accounting.update_journal_entry_with_lines(journal_entry, entry_attrs, lines)
      end
    else
      # If journal entry doesn't exist, create it
      record_order_payment(payment)
    end
  end

  # ── Revenue & COGS breakdowns ─────────────────────────────────────────

  def shipping_fee_cents do
    case Repo.get_by(Product, sku: @shipping_product_sku) do
      nil -> 0
      %Product{price_cents: cents} -> cents || 0
    end
  end

  # Get revenue breakdown by product
  def revenue_by_product(start_date, end_date) do
    fallback_shipping_fee = shipping_fee_cents()

    from(o in Order,
      join: p in assoc(o, :product),
      where: fragment("COALESCE(?, ?)", o.actual_delivery_date, o.delivery_date) >= ^start_date and fragment("COALESCE(?, ?)", o.actual_delivery_date, o.delivery_date) <= ^end_date and o.status == "delivered",
      group_by: [p.id, p.name, p.sku],
      select: %{
        product_id: p.id,
        product_name: p.name,
        product_sku: p.sku,
        revenue_cents: fragment("SUM(? * COALESCE(?, 1)) + SUM(CASE WHEN ? THEN COALESCE(?, ?) ELSE 0 END)", p.price_cents, o.quantity, o.customer_paid_shipping, o.shipping_fee_cents, ^fallback_shipping_fee)
      }
    )
    |> Repo.all()
    |> Enum.map(fn %{revenue_cents: cents} = row ->
      # Handle Decimal or integer result from fragment
      revenue_cents = if is_integer(cents), do: cents, else: Decimal.to_integer(cents)
      Map.put(row, :revenue_cents, revenue_cents)
    end)
  end

  # Get COGS breakdown by product
  def cogs_by_product(start_date, end_date) do
    # Get all delivered orders in the period with their products
    orders =
      from(o in Order,
        join: p in assoc(o, :product),
        where: fragment("COALESCE(?, ?)", o.actual_delivery_date, o.delivery_date) >= ^start_date and fragment("COALESCE(?, ?)", o.actual_delivery_date, o.delivery_date) <= ^end_date and o.status == "delivered",
        select: {o.id, p.id, p.name, p.sku}
      )
      |> Repo.all()

    # Get COGS for each order from journal entries
    order_ids = Enum.map(orders, fn {id, _, _, _} -> id end)

    cogs_map =
      if Enum.empty?(order_ids) do
        %{}
      else
        # Build OR conditions for order references
        reference_patterns = Enum.map(order_ids, fn id -> "Order ##{id}" end)

        base_query =
          from(je in JournalEntry,
            join: jl in assoc(je, :journal_lines),
            join: acc in assoc(jl, :account),
            where:
              je.entry_type == "order_delivered" and
                acc.code == "5000" and
                je.date >= ^start_date and
                je.date <= ^end_date
          )

        # Use exact matching with IN clause instead of ilike patterns
        # ilike("Order #1") would wrongly match "Order #10", "Order #11", etc.
        query =
          case reference_patterns do
            [] ->
              base_query
            patterns ->
              base_query
              |> where([je], je.reference in ^patterns)
          end

        from([je, jl, acc] in query,
          group_by: je.reference,
          select: {je.reference, sum(jl.debit_cents)}
        )
        |> Repo.all()
        |> Enum.into(%{}, fn {ref, cogs} ->
          # Extract order ID from reference like "Order #123"
          order_id =
            case Regex.run(~r/#(\d+)/, ref) do
              [_, id_str] -> String.to_integer(id_str)
              _ -> nil
            end
          {order_id, cogs || 0}
        end)
      end

    # Group COGS by product
    orders
    |> Enum.reduce(%{}, fn {order_id, product_id, product_name, product_sku}, acc ->
      cogs_cents = Map.get(cogs_map, order_id, 0)
      key = {product_id, product_name, product_sku}

      Map.update(acc, key, cogs_cents, &(&1 + cogs_cents))
    end)
    |> Enum.map(fn {{product_id, product_name, product_sku}, cogs_cents} ->
      %{
        product_id: product_id,
        product_name: product_name,
        product_sku: product_sku,
        cogs_cents: cogs_cents
      }
    end)
    |> Enum.sort_by(& &1.product_name)
  end

  # ── Private helpers ───────────────────────────────────────────────────

  defp do_record_order_delivered(order, reference) do
    order = Repo.preload(order, :product)

    if order.is_gift do
      do_record_gift_order_delivered(order, reference)
    else
      do_record_sale_order_delivered(order, reference)
    end
  end

  defp do_record_gift_order_delivered(order, reference) do
    wip = Accounting.get_account_by_code!(@wip_inventory_code)
    samples_gifts = Accounting.get_account_by_code!(@samples_gifts_code)
    cost_cents = get_order_production_cost(order.id, wip.id) || 0
    date = order.actual_delivery_date || order.delivery_date || Date.utc_today()

    entry_attrs = %{
      date: date,
      entry_type: "order_delivered",
      reference: reference,
      description: "Gift/sample order ##{order.id} delivered"
    }

    lines =
      if cost_cents > 0 do
        [
          %{
            account_id: samples_gifts.id,
            debit_cents: cost_cents,
            credit_cents: 0,
            description: "Samples & Gifts expense for order ##{order.id}"
          },
          %{
            account_id: wip.id,
            debit_cents: 0,
            credit_cents: cost_cents,
            description: "Relieve WIP for gift order ##{order.id}"
          }
        ]
      else
        []
      end

    Accounting.create_journal_entry_with_lines(entry_attrs, lines)
  end

  defp do_record_sale_order_delivered(order, reference) do
    quantity = order.quantity || 1
    gross_product_price = (order.product.price_cents || 0) * quantity

    # Calculate discount using the Orders context helper
    {discounted_product_price, shipping_cents} =
      Ledgr.Domains.MrMunchMe.Orders.order_total_cents(order)

    discount_cents = gross_product_price - discounted_product_price

    # Gross revenue = full product price + shipping (before discounts)
    gross_revenue_cents = gross_product_price + shipping_cents

    # Net revenue = discounted product price + shipping (what the customer actually owes)
    net_revenue_cents = discounted_product_price + shipping_cents

    # Get the production cost from the "order_in_prep" journal entry (WIP debit)
    # This was recorded when the order moved to "in_prep"
    wip = Accounting.get_account_by_code!(@wip_inventory_code)
    cost_cents = get_order_production_cost(order.id, wip.id) || 0

    ar    = Accounting.get_account_by_code!(@ar_code)
    sales = Accounting.get_account_by_code!(@sales_code)
    customer_deposits = Accounting.get_account_by_code!(@customer_deposits_code)

    ingredients_cogs = Accounting.get_account_by_code!(@ingredients_cogs_code)
    packing_cogs = Accounting.get_account_by_code!(@packing_cogs_code)

    date = order.actual_delivery_date || order.delivery_date || Date.utc_today()

    entry_attrs = %{
      date: date,
      entry_type: "order_delivered",
      reference: reference,
      description: "Delivered order ##{order.id}"
    }

    # Calculate total payments received before delivery
    delivery_date = order.actual_delivery_date || order.delivery_date || Date.utc_today()

    # Deposits are payments where is_deposit == true
    # Use customer_amount_cents if set, otherwise use amount_cents
    deposit_total_cents =
      from(p in OrderPayment,
        where: p.order_id == ^order.id and p.is_deposit == true,
        where: p.payment_date <= ^delivery_date,
        select: sum(fragment("COALESCE(?, ?)", p.customer_amount_cents, p.amount_cents))
      )
      |> Repo.one()
      |> case do
        nil -> 0
        total -> total
      end

    # Non-deposit payments received before delivery
    # These already credited AR, so we need to account for them
    non_deposit_payments_before_delivery_cents =
      from(p in OrderPayment,
        where: p.order_id == ^order.id and p.is_deposit == false,
        where: p.payment_date <= ^delivery_date,
        select: sum(fragment("COALESCE(?, ?)", p.customer_amount_cents, p.amount_cents))
      )
      |> Repo.one()
      |> case do
        nil -> 0
        total -> total
      end

    # Net AR to recognize = net revenue (after discount) - deposits - pre-delivery payments
    net_ar_cents = net_revenue_cents - deposit_total_cents - non_deposit_payments_before_delivery_cents

    # 1) Revenue recognition:
    #    CR Sales (4000) for gross revenue (full product price + shipping)
    #    DR Sales Discounts (4010) for discount amount (contra-revenue)
    #    DR AR (1100) for net amount owed by customer
    #
    # Accounting best practice: record gross sales and discount separately
    # so discount impact is visible on P&L. Net Revenue = Sales - Sales Discounts.
    revenue_lines =
      if gross_revenue_cents > 0 do
        base_lines = [
          %{
            account_id: ar.id,
            debit_cents: net_ar_cents,
            credit_cents: 0,
            description: "Recognize AR for order ##{order.id} (net of discounts & pre-delivery payments)"
          },
          %{
            account_id: sales.id,
            debit_cents: 0,
            credit_cents: gross_revenue_cents,
            description:
              if shipping_cents > 0 do
                "Gross sales (product + shipping) for order ##{order.id}"
              else
                "Gross sales revenue for order ##{order.id}"
              end
          }
        ]

        # Add contra-revenue discount line if there's a discount
        if discount_cents > 0 do
          sales_discounts = Accounting.get_account_by_code!(@sales_discounts_code)
          base_lines ++ [
            %{
              account_id: sales_discounts.id,
              debit_cents: discount_cents,
              credit_cents: 0,
              description: "Sales discount for order ##{order.id}"
            }
          ]
        else
          base_lines
        end
      else
        []
      end

    # 2) Transfer deposits from Customer Deposits to AR
    # When order is delivered, deposits should reduce AR
    # DR Customer Deposits, CR AR
    deposit_transfer_lines =
      if deposit_total_cents > 0 do
        [
          %{
            account_id: customer_deposits.id,
            debit_cents: deposit_total_cents,
            credit_cents: 0,
            description: "Transfer Customer Deposits to AR for order ##{order.id}"
          },
          %{
            account_id: ar.id,
            debit_cents: 0,
            credit_cents: deposit_total_cents,
            description: "Reduce AR by deposit amount for order ##{order.id}"
          }
        ]
      else
        []
      end

    # 3) COGS: DR COGS (split by type), CR WIP
    # Retrieve cost breakdown from the "order_in_prep" journal entry credit lines
    # to split COGS between Ingredients (5000) and Packaging (5010).
    # Kitchen costs (1300) are included with Ingredients COGS (5000).
    cogs_lines =
      if cost_cents > 0 do
        cost_split = get_order_production_cost_breakdown(order.id)

        cogs_debit_lines =
          [
            {ingredients_cogs, (cost_split.ingredients || 0) + (cost_split.kitchen || 0),
             "Ingredients COGS"},
            {packing_cogs, cost_split.packing || 0, "Packaging COGS"}
          ]
          |> Enum.filter(fn {_account, cents, _label} -> cents > 0 end)
          |> Enum.map(fn {account, cents, label} ->
            %{
              account_id: account.id,
              debit_cents: cents,
              credit_cents: 0,
              description: "#{label} for order ##{order.id}"
            }
          end)

        wip_credit_line = %{
          account_id: wip.id,
          debit_cents: 0,
          credit_cents: cost_cents,
          description: "Relieve WIP for order ##{order.id}"
        }

        cogs_debit_lines ++ [wip_credit_line]
      else
        []
      end

    lines = revenue_lines ++ deposit_transfer_lines ++ cogs_lines

    Accounting.create_journal_entry_with_lines(entry_attrs, lines)
  end

  defp build_payment_journal_lines(paid_to, order, payment, total_amount, customer_amount, partner_amount) do
    # Always debit the cash/receiving account for the total amount
    debit_line = %{
      account_id: paid_to.id,
      debit_cents: total_amount,
      credit_cents: 0,
      description: "Payment received (#{paid_to.code} – #{paid_to.name})"
    }

    # Build credit lines based on split payment
    credit_lines = if partner_amount > 0 do
      # Split payment: customer portion goes to AR, partner portion goes to Accounts Payable
      ar_account = if payment.is_deposit do
        Accounting.get_account_by_code!(@customer_deposits_code)
      else
        Accounting.get_account_by_code!(@ar_code)
      end

      partner_account = payment.partner_payable_account

      if is_nil(partner_account) do
        raise ArgumentError, "Partner payable account is required for split payments. Payment ID: #{payment.id}, Partner ID: #{payment.partner_id}"
      end

      partner_name = if payment.partner, do: payment.partner.name, else: "Partner"

      [
        %{
          account_id: ar_account.id,
          debit_cents: 0,
          credit_cents: customer_amount,
          description: if payment.is_deposit do
            "Increase Customer Deposits for order ##{order.id} (customer portion)"
          else
            "Reduce Accounts Receivable for order ##{order.id} (customer portion)"
          end
        },
        %{
          account_id: partner_account.id,
          debit_cents: 0,
          credit_cents: partner_amount,
          description: "Accounts Payable to #{partner_name} for order ##{order.id}"
        }
      ]
    else
      # Regular payment: all goes to AR or Customer Deposits
      ar_account = if payment.is_deposit do
        Accounting.get_account_by_code!(@customer_deposits_code)
      else
        Accounting.get_account_by_code!(@ar_code)
      end

      [
        %{
          account_id: ar_account.id,
          debit_cents: 0,
          credit_cents: total_amount,
          description: if payment.is_deposit do
            "Increase Customer Deposits for order ##{order.id}"
          else
            "Reduce Accounts Receivable for order ##{order.id}"
          end
        }
      ]
    end

    [debit_line | credit_lines]
  end

  # Get the production cost for an order from the "order_in_prep" journal entry
  # Returns the WIP debit amount, or nil if no journal entry exists
  defp get_order_production_cost(order_id, wip_account_id) do
    reference = "Order ##{order_id}"

    Repo.one(
      from je in JournalEntry,
        join: jl in assoc(je, :journal_lines),
        where: je.entry_type == "order_in_prep" and je.reference == ^reference,
        where: jl.account_id == ^wip_account_id and jl.debit_cents > 0,
        select: jl.debit_cents,
        limit: 1
    )
  end

  # Get the production cost breakdown by inventory type from the "order_in_prep" journal entry.
  # Returns %{ingredients: cents, packing: cents, kitchen: cents} by reading the credit lines
  # which correspond to the inventory accounts (1200, 1210, 1300).
  defp get_order_production_cost_breakdown(order_id) do
    reference = "Order ##{order_id}"

    ingredients_account = Accounting.get_account_by_code!(@ingredients_inventory_code)
    packing_account = Accounting.get_account_by_code!(@packing_inventory_code)
    kitchen_account = Accounting.get_account_by_code!(@kitchen_inventory_code)

    credit_lines =
      from(je in JournalEntry,
        join: jl in JournalLine,
        on: jl.journal_entry_id == je.id,
        where: je.entry_type == "order_in_prep" and je.reference == ^reference,
        where: jl.credit_cents > 0,
        select: {jl.account_id, jl.credit_cents}
      )
      |> Repo.all()
      |> Enum.into(%{})

    %{
      ingredients: Map.get(credit_lines, ingredients_account.id, 0),
      packing: Map.get(credit_lines, packing_account.id, 0),
      kitchen: Map.get(credit_lines, kitchen_account.id, 0)
    }
  end
end
