defmodule MrMunchMeAccountingApp.Inventory do
  @moduledoc """
  Inventory logic: ingredients, locations, stock levels (per location),
  and movements with dynamic moving-average costing.
  """
  require Logger
  import Ecto.Query
  alias MrMunchMeAccountingApp.Repo
  alias MrMunchMeAccountingApp.Accounting
  alias MrMunchMeAccountingApp.Accounting.JournalEntry
  alias MrMunchMeAccountingApp.Orders
  alias MrMunchMeAccountingApp.Orders.Order
  alias __MODULE__.{Ingredient, Location, InventoryItem, InventoryMovement, PurchaseForm, PurchaseListForm, MovementForm, MovementListForm, Recepies, PurchaseItemForm, MovementItemForm}


  # ---------- Helper functions ----------

  # Calculates the cumulative average cost from all purchase movements.
  # Returns: total_spent / total_purchased = sum(purchase total_cost_cents) / sum(purchase quantities)
  defp calculate_cumulative_avg_cost(ingredient_id, location_id) do
    result =
      from(m in InventoryMovement,
        where: m.ingredient_id == ^ingredient_id,
        where: m.to_location_id == ^location_id,
        where: m.movement_type == "purchase",
        select: %{
          total_cost: fragment("COALESCE(SUM(?), 0)", m.total_cost_cents),
          total_quantity: fragment("COALESCE(SUM(?), 0)", m.quantity)
        }
      )
      |> Repo.one()

    # Convert Decimal values from SQL SUM to integers
    total_cost = case result do
      %{total_cost: cost} when is_integer(cost) -> cost
      %{total_cost: %Decimal{} = cost} -> Decimal.to_integer(cost)
      _ -> 0
    end

    total_quantity = case result do
      %{total_quantity: qty} when is_integer(qty) -> qty
      %{total_quantity: %Decimal{} = qty} -> Decimal.to_integer(qty)
      _ -> 0
    end

    case {total_cost, total_quantity} do
      {0, 0} -> nil
      {_, 0} -> nil
      {cost, qty} when qty > 0 ->
        exact_avg = cost / qty
        round(exact_avg)
      _ -> nil
    end
  end

  # Calculates the weighted average cost per unit, rounded to the nearest cent.
  # Uses floating point division and proper rounding to avoid precision loss.
  # DEPRECATED: Use calculate_cumulative_avg_cost instead for actual purchase costs.
  defp calculate_weighted_avg_cost(old_qty, old_cost_cents, new_qty_added, new_unit_cost_cents, total_new_qty) do
    if total_new_qty <= 0 do
      new_unit_cost_cents
    else
      # Calculate exact average using floating point division
      total_cost = old_qty * old_cost_cents + new_qty_added * new_unit_cost_cents
      exact_avg = total_cost / total_new_qty
      # Round to nearest cent
      round(exact_avg)
    end
  end


  # ---------- Lookups ----------

  def get_ingredient_by_code!(code), do: Repo.get_by!(Ingredient, code: code)
  def get_location_by_code!(code), do: Repo.get_by!(Location, code: code)

  # ---------- INGREDIENTS ----------

  def list_ingredients do
    Repo.all(from i in Ingredient, order_by: i.name)
  end

  def get_ingredient!(id), do: Repo.get!(Ingredient, id)

  def change_ingredient(%Ingredient{} = ingredient, attrs \\ %{}) do
    Ingredient.changeset(ingredient, attrs)
  end

  def create_ingredient(attrs) do
    %Ingredient{}
    |> Ingredient.changeset(attrs)
    |> Repo.insert()
  end

  def update_ingredient(%Ingredient{} = ingredient, attrs) do
    ingredient
    |> Ingredient.changeset(attrs)
    |> Repo.update()
  end

  def delete_ingredient(%Ingredient{} = ingredient) do
    Repo.delete(ingredient)
  end

  def get_or_create_stock!(ingredient_id, location_id) do
    case Repo.get_by(InventoryItem, ingredient_id: ingredient_id, location_id: location_id) do
      nil ->
        %InventoryItem{}
        |> InventoryItem.changeset(%{
          ingredient_id: ingredient_id,
          location_id: location_id,
          quantity_on_hand: 0,
          avg_cost_per_unit_cents: 0
        })
        |> Repo.insert!()

      stock ->
        stock
    end
  end

  # ---------- PURCHASE (dynamic moving average) ----------

  @doc """
  Record a purchase of an ingredient into a location, updating
  quantity_on_hand and avg_cost_per_unit_cents (moving average).

  Arguments:
    - ingredient_code: "FLOUR"
    - location_code:   "WAREHOUSE"
    - quantity:        integer in base units (e.g. grams)
    - unit_cost_cents: cost per unit of this batch
    - source_type:     "expense" | "manual"
    - source_id:       e.g. expense_id
  """
  def record_purchase(
      ingredient_code,
      location_code,
      quantity,
      paid_from_account_id,
      unit_cost_cents,
      purchase_date,
      source_type \\ nil,
      source_id \\ nil,
      total_cost_cents \\ nil
    ) do
    Repo.transaction(fn ->
      do_record_purchase(
        ingredient_code,
        location_code,
        quantity,
        paid_from_account_id,
        unit_cost_cents,
        purchase_date,
        source_type,
        source_id,
        total_cost_cents
      )
    end)
  end

  # Internal function that does the actual work without managing transactions
  defp do_record_purchase(
         ingredient_code,
         location_code,
         quantity,
         paid_from_account_id,
         unit_cost_cents,
         purchase_date,
         source_type,
         source_id,
         total_cost_cents
       ) do
    ingredient = get_ingredient_by_code!(ingredient_code)
    location   = get_location_by_code!(location_code)
    paid_from_account = Accounting.get_account!(paid_from_account_id)

    stock = get_or_create_stock!(ingredient.id, location.id)

    old_qty  = stock.quantity_on_hand
    new_qty  = old_qty + quantity

    # Use provided total_cost_cents if available (actual purchase cost),
    # otherwise calculate from unit_cost_cents (for backward compatibility)
    actual_total_cost_cents = total_cost_cents || (quantity * unit_cost_cents)

    # 1) Insert movement first
    {:ok, movement} =
      %InventoryMovement{}
      |> InventoryMovement.changeset(%{
        ingredient_id: ingredient.id,
        from_location_id: nil,
        to_location_id: location.id,
        paid_from_account_id: paid_from_account.id,
        quantity: quantity,
        movement_type: "purchase",
        unit_cost_cents: unit_cost_cents,
        total_cost_cents: actual_total_cost_cents,
        source_type: source_type,
        source_id: source_id,
        note: "Purchase into #{location.code}",
        movement_date: purchase_date
      })
      |> Repo.insert()

    # 2) Calculate cumulative average from all purchase movements (including the one we just inserted)
    new_avg_cost = calculate_cumulative_avg_cost(ingredient.id, location.id) || unit_cost_cents

    # 3) Update stock with new quantity and cumulative average cost
    stock
    |> InventoryItem.changeset(%{
      quantity_on_hand: new_qty,
      avg_cost_per_unit_cents: new_avg_cost
    })
    |> Repo.update!()

    {:ok, %{movement: movement, stock: stock}}
  end

  # ---------- USAGE (consuming inventory for orders, etc.) ----------

  @doc """
  Consume inventory from a location at its current avg cost.
  Returns {total_cost_cents, new_stock}.
  """
  def record_usage(ingredient_code, location_code, quantity, movement_date, source_type \\ nil, source_id \\ nil) do

    Repo.transaction(fn ->
      ingredient = get_ingredient_by_code!(ingredient_code)
      location   = get_location_by_code!(location_code)

      stock = get_or_create_stock!(ingredient.id, location.id)

      # TODO: Uncomment this when we have a way to handle insufficient stock
      # if stock.quantity_on_hand < quantity do
      #   Repo.rollback({:error, :insufficient_stock})
      # end

      # Use current average cost
      unit_cost_cents = stock.avg_cost_per_unit_cents
      total_cost_cents = quantity * unit_cost_cents

      new_qty = stock.quantity_on_hand - quantity

      {:ok, movement} =
        %InventoryMovement{}
        |> InventoryMovement.changeset(%{
          ingredient_id: ingredient.id,
          from_location_id: location.id,
          to_location_id: nil,
          quantity: quantity,
          movement_type: "usage",
          unit_cost_cents: unit_cost_cents,
          total_cost_cents: total_cost_cents,
          source_type: source_type,
          source_id: source_id,
          note: "Usage from #{location.code}",
          movement_date: movement_date
        })
        |> Repo.insert()

      stock =
        stock
        |> InventoryItem.changeset(%{quantity_on_hand: new_qty})
        |> Repo.update!()

      # Create journal entry for manual usage (not for orders, which go through WIP)
      if source_type != "order" do
        # Determine inventory type for accounting
        inv_type = inventory_type(ingredient.code)
        packing? = inv_type == :packing
        kitchen? = inv_type == :kitchen

        Accounting.record_inventory_usage(
          total_cost_cents,
          usage_date: movement_date,
          reference: "Usage #{ingredient_code} @ #{location_code}",
          packing: packing?,
          kitchen: kitchen?,
          description: "Manual usage of #{quantity} #{ingredient_code} from #{location_code}"
        )
      end

      {:ok, %{movement: movement, stock: stock, total_cost_cents: total_cost_cents}}
    end)
  end

  @doc """
  Consumes ingredient inventory for an order based on its recipe.

  Returns total cost in cents of all ingredients used.

  Assumes the order has product preloaded (or preloads it).
  """
  @production_location_code "CASA_AG"
  def consume_for_order(%Order{} = order) do
    order = Repo.preload(order, :product)

    # Use the order's delivery_date (or in_prep date) to get the active recipe
    recipe_date = order.delivery_date || Date.utc_today()
    recipe_lines = Recepies.recipe_for_product(order.product, recipe_date)
    location_code =
      case order.prep_location do
        %Location{code: code} when is_binary(code) -> code
        _ -> @production_location_code #default fallback
      end

    Enum.reduce(recipe_lines, 0, fn %{ingredient_code: code, quantity: qty}, acc ->
      # Convert float quantity to integer (round to nearest)
      qty_int = round(qty)

      case record_usage(code, location_code, qty_int, order.delivery_date, "order", order.id) do
        {:ok, {:ok, result}} ->
          acc + result.movement.total_cost_cents

        {:ok, movement} -> #safeguard
          acc + movement.total_cost_cents

        {:error, reason} ->
          # For now we can either raise/rollback or ignore. Safer to raise:
          raise "Failed to record usage for ingredient #{code} in order #{order.id}: #{inspect(reason)}"
      end
    end)
  end

  @doc """
  Returns required ingredients per *prep location* for all `new_order` orders.

  Output:

  [
    %{
      location_id: 1,
      location_name: "Kitchen",
      ingredient_id: 10,
      ingredient_name: "Flour",
      unit: "g",
      total_required: 3500,
      on_hand: 1200,
      shortage: 2300
    },
    ...
  ]

  - `total_required` = sum of recipe quantities for all NEW orders assigned to that prep_location
  - `on_hand` = sum of inventory for that ingredient at that location
  - `shortage` = max(total_required - on_hand, 0)
  """
  def required_ingredients_for_new_orders do
    # 1) Get all NEW orders with product + prep_location preloaded
    orders =
      Orders.list_orders(%{"status" => "new_order"})
      |> Repo.preload([:product, :prep_location])

    # 2) Expand orders into per-ingredient, per-location requirements
    raw_needs =
      Enum.flat_map(orders, fn %Order{} = order ->
        # Use the order's delivery_date to get the active recipe at that time
        recipe_date = order.delivery_date || Date.utc_today()
        recipe = Recepies.recipe_for_product(order.product, recipe_date)

        prep_location_id = order.prep_location_id || @production_location_code

        Enum.map(recipe, fn line ->
          code = Map.get(line, :ingredient_code) || Map.get(line, "ingredient_code")
          qty = Map.get(line, :quantity) || Map.get(line, "quantity") || 0

          %{
            ingredient_code: code,
            quantity: qty,
            location_id: prep_location_id,
            delivery_date: order.delivery_date
          }
        end)
      end)

    # 3) Group by {ingredient_code, location_id} and aggregate
    raw_needs
    |> Enum.group_by(fn %{ingredient_code: code, location_id: loc_id} ->
      {code, loc_id}
    end)
    |> Enum.map(fn {{code, location_id}, entries} ->
      total_required =
        Enum.reduce(entries, 0, fn %{quantity: q}, acc -> acc + (q || 0) end)

      ingredient = get_ingredient_by_code!(code)
      location   = Repo.get!(Location, location_id)

      # On-hand only at THIS location
      on_hand =
        InventoryItem
        |> where([i], i.ingredient_id == ^ingredient.id and i.location_id == ^location_id)
        |> select([i], coalesce(sum(i.quantity_on_hand), 0))
        |> Repo.one()

      shortage = max(total_required - on_hand, 0)

      # 🔹 EARLIEST delivery date among orders using this ingredient at this location
      needed_by =
        entries
        |> Enum.map(& &1.delivery_date)
        |> Enum.reject(&is_nil/1)
        |> case do
          [] -> nil
          dates -> Enum.min(dates)
        end

      %{
        location_id: location.id,
        location_name: location.name,
        location: location,
        ingredient_id: ingredient.id,
        ingredient_name: ingredient.name,
        unit: ingredient.unit,
        total_required: total_required,
        on_hand: on_hand,
        shortage: shortage,
        needed_by: needed_by
      }
    end)
  end

  # ---------- TRANSFER between locations ----------

  @doc """
  Transfer quantity between locations; cost is moved, not recomputed.
  Uses the avg cost from the origin location and updates both stocks.
  """
  def transfer(ingredient_code, from_location_code, to_location_code, quantity, movement_date, source_type \\ nil, source_id \\ nil) do
    Repo.transaction(fn ->
      ingredient = get_ingredient_by_code!(ingredient_code)
      from_loc   = get_location_by_code!(from_location_code)
      to_loc     = get_location_by_code!(to_location_code)

      from_stock = get_or_create_stock!(ingredient.id, from_loc.id)
      to_stock   = get_or_create_stock!(ingredient.id, to_loc.id)

      if from_stock.quantity_on_hand < quantity, do: Repo.rollback({:error, :insufficient_stock})

      # Use average cost from origin location
      unit_cost_cents = from_stock.avg_cost_per_unit_cents
      total_cost_cents = quantity * unit_cost_cents

      # out of from_loc
      new_from_qty = from_stock.quantity_on_hand - quantity
      from_stock =
        from_stock
        |> InventoryItem.changeset(%{quantity_on_hand: new_from_qty})
        |> Repo.update!()

      # into to_loc (as if we "purchased" at that unit cost)
      old_to_qty  = to_stock.quantity_on_hand
      old_to_cost = to_stock.avg_cost_per_unit_cents
      new_to_qty  = old_to_qty + quantity

      new_to_avg_cost = calculate_weighted_avg_cost(old_to_qty, old_to_cost, quantity, unit_cost_cents, new_to_qty)

      to_stock =
        to_stock
        |> InventoryItem.changeset(%{
          quantity_on_hand: new_to_qty,
          avg_cost_per_unit_cents: new_to_avg_cost
        })
        |> Repo.update!()

      # movement record
      {:ok, movement} =
        %InventoryMovement{}
        |> InventoryMovement.changeset(%{
          ingredient_id: ingredient.id,
          from_location_id: from_loc.id,
          to_location_id: to_loc.id,
          quantity: quantity,
          movement_type: "transfer",
          unit_cost_cents: unit_cost_cents,
          total_cost_cents: total_cost_cents,
          source_type: source_type,
          source_id: source_id,
          note: "Transfer #{quantity} from #{from_loc.code} to #{to_loc.code}",
          movement_date: movement_date
        })
        |> Repo.insert()

      {:ok, %{movement: movement, from_stock: from_stock, to_stock: to_stock}}
    end)
  end


  # ---------- Dashboard helpers ----------

  @packing_codes ["BOLSA_CELOFAN", "ESTAMPAS", "LISTONES", "BASE_GRANDE", "BASE_MEDIANA"]
  @kitchen_codes ["MOLDE_GRANDE", "MOLDE_MEDIANO"]

  @doc """
  Determines the inventory type based on ingredient code.
  Returns :packing, :kitchen, or :ingredients
  """
  def inventory_type(ingredient_code) when is_binary(ingredient_code) do
    cond do
      ingredient_code in @packing_codes -> :packing
      ingredient_code in @kitchen_codes -> :kitchen
      true -> :ingredients
    end
  end

  def inventory_type(%{code: code}), do: inventory_type(code)
  def inventory_type(%{ingredient: %{code: code}}), do: inventory_type(code)

  @doc """
  Returns all stock items, preloaded with ingredient + location.
  One row per (ingredient, location).
  """
  def list_stock_items do
    InventoryItem
    |> preload([:ingredient, :location])
    |> Repo.all()
  end

  @doc """
  Calculate the actual inventory value for a specific ingredient+location pair
  based on purchase costs minus consumption costs, accounting for transfers.
  Returns the actual cost of remaining inventory for this ingredient+location.
  """
  def inventory_item_value_cents(ingredient_id, location_id) do
    # Sum purchase costs for this ingredient+location
    purchase_total =
      from(m in InventoryMovement,
        where: m.movement_type == "purchase",
        where: m.ingredient_id == ^ingredient_id,
        where: m.to_location_id == ^location_id,
        select: coalesce(sum(m.total_cost_cents), 0)
      )
      |> Repo.one()

    # Sum consumption costs (usage + write_off) for this ingredient+location
    consumption_total =
      from(m in InventoryMovement,
        where: m.movement_type in ["usage", "write_off"],
        where: m.ingredient_id == ^ingredient_id,
        where: m.from_location_id == ^location_id,
        select: coalesce(sum(m.total_cost_cents), 0)
      )
      |> Repo.one()

    # Sum transfers OUT of this location (subtract)
    transfer_out_total =
      from(m in InventoryMovement,
        where: m.movement_type == "transfer",
        where: m.ingredient_id == ^ingredient_id,
        where: m.from_location_id == ^location_id,
        select: coalesce(sum(m.total_cost_cents), 0)
      )
      |> Repo.one()

    # Sum transfers IN to this location (add)
    transfer_in_total =
      from(m in InventoryMovement,
        where: m.movement_type == "transfer",
        where: m.ingredient_id == ^ingredient_id,
        where: m.to_location_id == ^location_id,
        select: coalesce(sum(m.total_cost_cents), 0)
      )
      |> Repo.one()

    # Convert Decimal to integer if needed
    purchase_cents = case purchase_total do
      %Decimal{} = dec -> Decimal.to_integer(dec)
      int when is_integer(int) -> int
      _ -> 0
    end

    consumption_cents = case consumption_total do
      %Decimal{} = dec -> Decimal.to_integer(dec)
      int when is_integer(int) -> int
      _ -> 0
    end

    transfer_out_cents = case transfer_out_total do
      %Decimal{} = dec -> Decimal.to_integer(dec)
      int when is_integer(int) -> int
      _ -> 0
    end

    transfer_in_cents = case transfer_in_total do
      %Decimal{} = dec -> Decimal.to_integer(dec)
      int when is_integer(int) -> int
      _ -> 0
    end

    purchase_cents + transfer_in_cents - consumption_cents - transfer_out_cents
  end

  @doc """
  Total inventory value calculated from actual purchase costs.
  Formula: sum(all purchase total_cost_cents) - sum(all usage/write_off total_cost_cents)
  This gives the actual cost of remaining inventory based on what was actually spent.
  """
  def total_inventory_value_cents do
    # Sum all purchase costs
    purchase_total =
      from(m in InventoryMovement,
        where: m.movement_type == "purchase",
        select: coalesce(sum(m.total_cost_cents), 0)
      )
      |> Repo.one()

    # Sum all consumption costs (usage + write_off)
    consumption_total =
      from(m in InventoryMovement,
        where: m.movement_type in ["usage", "write_off"],
        select: coalesce(sum(m.total_cost_cents), 0)
      )
      |> Repo.one()

    # Convert Decimal to integer if needed
    purchase_cents = case purchase_total do
      %Decimal{} = dec -> Decimal.to_integer(dec)
      int when is_integer(int) -> int
      _ -> 0
    end

    consumption_cents = case consumption_total do
      %Decimal{} = dec -> Decimal.to_integer(dec)
      int when is_integer(int) -> int
      _ -> 0
    end

    purchase_cents - consumption_cents
  end

  @doc """
  Latest N inventory movements, with ingredient and locations preloaded.
  """
  def list_recent_movements(limit \\ 10) do
    InventoryMovement
    |> order_by([m], desc: m.inserted_at)
    |> limit(^limit)
    |> preload([:ingredient, :from_location, :to_location])
    |> Repo.all()
  end

  @doc """
  Check if there are more movements beyond the current limit.
  """
  def has_more_movements?(current_limit) do
    total_count =
      from(m in InventoryMovement, select: count(m.id))
      |> Repo.one()

    total_count > current_limit
  end

  @doc """
  Get a single inventory movement by id, preloaded with associations.
  """
  def get_movement!(id) do
    InventoryMovement
    |> Repo.get!(id)
    |> Repo.preload([:ingredient, :from_location, :to_location, :paid_from_account])
  end

  @doc """
  All locations (if you want to use them later for filters, etc.).
  """
  def list_locations do
    Repo.all(Location)
  end

  # --- Select options for form ---

  def ingredient_select_options do
    Repo.all(Ingredient)
    |> Enum.map(fn ing ->
      {"#{ing.name} (#{ing.code})", ing.code}
    end)
  end

  def location_select_options do
    Repo.all(Location)
    |> Enum.map(fn loc ->
      {loc.name, loc.code}
    end)
  end

  # --- Purchase form helpers ---

  def change_purchase_form(attrs \\ %{}) do
    PurchaseForm.changeset(%PurchaseForm{}, attrs)
  end

  # --- Purchase list form helpers ---
  def change_purchase_list_form(attrs \\ %{}) do
    base_struct =
      case attrs do
        %{"items" => _} -> %PurchaseListForm{}
        %{:items => _} -> %PurchaseListForm{}
        _ -> %PurchaseListForm{items: [%PurchaseItemForm{}]}
      end

    PurchaseListForm.changeset(base_struct, attrs)
  end

  def create_purchase(attrs) do
    changeset = change_purchase_form(attrs)

    if changeset.valid? do
      form = Ecto.Changeset.apply_changes(changeset)

      # total cost in cents (MXN → cents)
      total_cost_cents =
        form.total_cost_pesos
        |> Decimal.mult(Decimal.new(100))
        |> Decimal.round(0)
        |> Decimal.to_integer()

      # derive unit cost from total / quantity (for moving average calculation)
      # Calculate with floating point and round to nearest cent to maintain precision
      unit_cost_cents =
        if form.quantity > 0 do
          exact_unit_cost = total_cost_cents / form.quantity
          round(exact_unit_cost)
        else
          0
        end


      # 1) Record the inventory side (movement + stock update)
      # Pass the actual total_cost_cents so it's stored correctly in the movement
      case record_purchase(
             form.ingredient_code,
             form.location_code,
             form.quantity,
             form.paid_from_account_id,
             unit_cost_cents,
             form.purchase_date,
             "manual",
             nil,
             total_cost_cents
           ) do
        {:ok, _movement} ->
          # 2) Record the accounting side
          inventory_type = inventory_type(form.ingredient_code)
          packing? = inventory_type == :packing
          kitchen? = inventory_type == :kitchen

          Accounting.record_inventory_purchase(
            total_cost_cents,
            purchase_date: form.purchase_date,
            paid_from_account_id: form.paid_from_account_id,
            reference: "Purchase #{form.ingredient_code} @ #{form.location_code}",
            packing: packing?,
            kitchen: kitchen?,
            description:
              "Purchase of #{form.quantity} #{form.ingredient_code} into #{form.location_code}"
          )

        {:error, reason} ->
          # If your record_purchase returns {:error, reason}, forward that
          {:error,
           change_purchase_form(attrs)
           |> Ecto.Changeset.add_error(:base, "Inventory purchase failed: #{inspect(reason)}")}
      end
    else
      {:error, changeset}
    end
  end

  def create_purchase_list(attrs) do
    Logger.debug("🧾 create_purchase_list called with attrs: #{inspect(attrs)}")

    changeset = change_purchase_list_form(attrs)

    if changeset.valid? do
      form = Ecto.Changeset.apply_changes(changeset)

      Logger.debug("✅ PurchaseListForm valid. Resolved form: #{inspect(form)}")

      tx_result =
        Repo.transaction(fn ->
          Enum.each(form.items, fn item ->
            item_attrs = %{
              "ingredient_code" => item.ingredient_code,
              "location_code" => form.location_code,
              "quantity" => item.quantity,
              "total_cost_pesos" => item.total_cost_pesos,
              "paid_from_account_id" => form.paid_from_account_id,
              "purchase_date" => form.purchase_date
            }

            Logger.debug("➡️ Calling create_purchase/1 for item: #{inspect(item_attrs)}")

            case create_purchase(item_attrs) do
              {:ok, result} ->
                Logger.debug("✅ create_purchase/1 OK: #{inspect(result)}")
                :ok

              {:error, item_changeset = %Ecto.Changeset{}} ->
                Logger.error("❌ create_purchase/1 returned changeset error: #{inspect(item_changeset.errors)}")
                Repo.rollback(item_changeset)

              {:error, other} ->
                Logger.error("❌ create_purchase/1 returned non-changeset error: #{inspect(other)}")
                Repo.rollback(other)
            end
          end)

          :ok
        end)

      Logger.debug("🔙 Repo.transaction result: #{inspect(tx_result)}")

      case tx_result do
        {:ok, _} ->
          {:ok, :ok}

        {:error, %Ecto.Changeset{} = item_changeset} ->
          Logger.error("❌ Transaction rolled back with item changeset: #{inspect(item_changeset.errors)}")
          {:error, item_changeset}

        {:error, reason} ->
          Logger.error("❌ Transaction rolled back with generic reason: #{inspect(reason)}")

        {:error,
          changeset
          |> Ecto.Changeset.add_error(:base, "Inventory purchase failed: #{inspect(reason)}")}
      end
    else
      Logger.error("❌ PurchaseListForm INVALID: #{inspect(changeset.errors)}")
      {:error, changeset}
    end
  end

  def ingredient_quick_infos do

    query =
      from i in Ingredient,
        left_join: inv in InventoryItem,
        on: inv.ingredient_id == i.id,
        group_by: [i.id, i.code, i.name, i.unit],
        select: %{
          code: i.code,
          unit: i.unit,
          # weighted avg across locations based only on actual purchases
          # returns NULL if no stock/purchases yet
          # uses ROUND() to avoid truncation and maintain precision
          avg_cost_cents:
            fragment(
              "CASE WHEN SUM(?) > 0 THEN ROUND(CAST(SUM(? * ?) AS NUMERIC) / SUM(?)) ELSE NULL END",
              inv.quantity_on_hand,
              inv.quantity_on_hand,
              inv.avg_cost_per_unit_cents,
              inv.quantity_on_hand
            )
        }

    query
    |> Repo.all()
    |> Map.new(fn row ->
      # Convert Decimal to integer for JSON encoding (ROUND() returns Decimal/NUMERIC type)
      avg_cost_cents =
        case row.avg_cost_cents do
          nil -> nil
          %Decimal{} = dec -> Decimal.to_integer(dec)
          other when is_integer(other) -> other
          other ->
            # Fallback: try to convert to integer
            case Integer.parse(to_string(other)) do
              {int, _} -> int
              :error -> nil
            end
        end

      {row.code,
       %{
         "unit" => row.unit,
         "avg_cost_cents" => avg_cost_cents
       }}
    end)
  end

  @doc """
  Get inventory quantities by ingredient code and location code.
  Returns a map of %{ingredient_code => %{location_code => quantity}}
  """
  def ingredient_location_stock do
    query =
      from i in Ingredient,
        left_join: inv in InventoryItem,
        on: inv.ingredient_id == i.id,
        left_join: loc in Location,
        on: inv.location_id == loc.id,
        select: %{
          ingredient_code: i.code,
          location_code: loc.code,
          quantity: inv.quantity_on_hand
        }

    query
    |> Repo.all()
    |> Enum.reduce(%{}, fn row, acc ->
      ingredient_code = row.ingredient_code
      location_code = row.location_code || ""
      quantity = row.quantity || 0

      acc
      |> Map.update(ingredient_code, %{location_code => quantity}, fn locations ->
        Map.put(locations, location_code, quantity)
      end)
    end)
  end


  # --- Movement form helpers ---

  def change_movement_form(attrs \\ %{}) do
    MovementForm.changeset(%MovementForm{}, attrs)
  end

  def change_movement_list_form(attrs \\ %{}) do
    base_struct =
      case attrs do
        %{"items" => _} -> %MovementListForm{}
        %{:items => _} -> %MovementListForm{}
        _ -> %MovementListForm{items: [%MovementItemForm{}]}
      end

    MovementListForm.changeset(base_struct, attrs)
  end

  @doc """
  Creates a manual inventory movement (usage or transfer) and delegates to
  the existing record_usage/transfer functions.

  Returns {:ok, result} or {:error, changeset}.
  """
  def create_movement(attrs) do
    changeset = change_movement_form(attrs)

    if changeset.valid? do
      form = Ecto.Changeset.apply_changes(changeset)

      case form.movement_type do
        "usage" ->
          case record_usage(
                 form.ingredient_code,
                 form.from_location_code,
                 form.quantity,
                 form.movement_date,
                 "manual",
                 nil
               ) do
            {:ok, result} -> {:ok, result}
            {:error, reason} ->
              {:error, Ecto.Changeset.add_error(changeset, :base, "Usage failed: #{inspect(reason)}")}
          end

        "transfer" ->
          case transfer(
                 form.ingredient_code,
                 form.from_location_code,
                 form.to_location_code,
                 form.quantity,
                 form.movement_date,
                 "manual",
                 nil
               ) do
            {:ok, result} -> {:ok, result}
            {:error, reason} ->
              {:error, Ecto.Changeset.add_error(changeset, :base, "Transfer failed: #{inspect(reason)}")}
          end

        "write_off" ->
          case record_write_off(
                 form.ingredient_code,
                 form.from_location_code,
                 form.quantity,
                 form.movement_date,
                 "manual",
                 nil
               ) do
            {:ok, result} -> {:ok, result}
            {:error, reason} ->
              {:error, Ecto.Changeset.add_error(changeset, :base, "Write-off failed: #{inspect(reason)}")}
          end
      end
    else
      {:error, changeset}
    end
  end

  def create_movement_list(attrs) do
    Logger.debug("🧾 create_movement_list called with attrs: #{inspect(attrs)}")

    changeset = change_movement_list_form(attrs)

    if changeset.valid? do
      form = Ecto.Changeset.apply_changes(changeset)

      Logger.debug("✅ MovementListForm valid. Resolved form: #{inspect(form)}")

      tx_result =
        Repo.transaction(fn ->
          Enum.each(form.items, fn item ->
            item_attrs = %{
              "movement_type" => form.movement_type,
              "ingredient_code" => item.ingredient_code,
              "from_location_code" => form.from_location_code,
              "to_location_code" => form.to_location_code,
              "quantity" => item.quantity,
              "movement_date" => form.movement_date,
              "note" => form.note
            }

            Logger.debug("➡️ Calling create_movement/1 for item: #{inspect(item_attrs)}")

            case create_movement(item_attrs) do
              {:ok, result} ->
                Logger.debug("✅ create_movement/1 OK: #{inspect(result)}")
                :ok

              {:error, item_changeset = %Ecto.Changeset{}} ->
                Logger.error("❌ create_movement/1 returned changeset error: #{inspect(item_changeset.errors)}")
                # Rollback with the inner error so the transaction stops
                Repo.rollback(item_changeset)

              {:error, other} ->
                Logger.error("❌ create_movement/1 returned non-changeset error: #{inspect(other)}")
                Repo.rollback(other)
            end
          end)

          :ok
        end)

      Logger.debug("🔙 Repo.transaction result: #{inspect(tx_result)}")

      case tx_result do
        {:ok, _} ->
          {:ok, :ok}

        # 🚨 THE CRITICAL FIX:
        # If the transaction fails with an inner item error, extract the error message
        # and add it to the parent changeset so it displays in the form.
        {:error, %Ecto.Changeset{} = inner_item_changeset} ->
          Logger.error("❌ Transaction rolled back with item changeset: #{inspect(inner_item_changeset.errors)}")

          # Extract base errors from the inner changeset
          base_errors = Keyword.get_values(inner_item_changeset.errors, :base)

          # Add the error to the parent changeset
          failed_changeset =
            Enum.reduce(base_errors, changeset, fn {msg, _opts}, acc ->
              Ecto.Changeset.add_error(acc, :base, msg)
            end)
            |> Map.put(:action, :insert)

          {:error, failed_changeset}

        {:error, reason} ->
          Logger.error("❌ Transaction rolled back with generic reason: #{inspect(reason)}")
          {:error, Ecto.Changeset.add_error(changeset, :base, "Inventory movement failed: #{inspect(reason)}")}
      end
    else
      Logger.error("❌ MovementListForm INVALID: #{inspect(changeset.errors)}")
      {:error, changeset}
    end
  end

  @doc """
  Write-off / waste: remove quantity from a location.

  This is similar to usage but semantically "thrown out".
  Later we can hook this to an accounting expense.
  """
  def record_write_off(
      ingredient_code,
      from_location_code,
      quantity,
      write_off_date,
      source_type \\ "manual",
      source_id \\ nil
    ) do
    ingredient = get_ingredient_by_code!(ingredient_code)
    location   = get_location_by_code!(from_location_code)

    Repo.transaction(fn ->
      stock = get_or_create_stock!(ingredient.id, location.id)

      if stock.quantity_on_hand < quantity do
        Repo.rollback(:insufficient_stock)
      end

      # Use current avg cost for write-off
      unit_cost_cents = stock.avg_cost_per_unit_cents
      total_cost_cents = unit_cost_cents * quantity

      # Insert movement
      movement_changeset =
        InventoryMovement.changeset(%InventoryMovement{}, %{
          ingredient_id: ingredient.id,
          from_location_id: location.id,
          to_location_id: nil,
          quantity: quantity,
          movement_type: "write_off",
          unit_cost_cents: unit_cost_cents,
          total_cost_cents: total_cost_cents,
          source_type: source_type,
          source_id: source_id,
          note: "Write-off (waste / thrown out)",
          movement_date: write_off_date
        })

      movement = Repo.insert!(movement_changeset)

      # Update stock
      new_qty = stock.quantity_on_hand - quantity

      stock
      |> InventoryItem.changeset(%{
        quantity_on_hand: new_qty
        # avg_cost_per_unit_cents stays the same: only quantity changes
      })
      |> Repo.update!()

      # Determine inventory type for accounting
      inv_type = inventory_type(ingredient.code)
      packing? = inv_type == :packing
      kitchen? = inv_type == :kitchen

      # Create journal entry for write-off
      Accounting.record_inventory_write_off(
        total_cost_cents,
        write_off_date: write_off_date,
        reference: "Write-off #{ingredient_code} @ #{from_location_code}",
        packing: packing?,
        kitchen: kitchen?,
        description: "Write-off of #{quantity} #{ingredient_code} from #{from_location_code} (waste/shrinkage)"
      )

      movement
    end)
  end

  # --- Purchase edit/delete helpers ---

  @doc """
  Delete a purchase movement. Reverses the inventory changes and deletes the journal entry.
  """
  def delete_purchase(movement_id) do
    movement = get_movement!(movement_id)

    if movement.movement_type != "purchase" do
      {:error, :not_a_purchase}
    else
      Repo.transaction(fn ->
        # Reverse the inventory changes
        ingredient = movement.ingredient
        location = movement.to_location
        stock = get_or_create_stock!(ingredient.id, location.id)

        old_qty = stock.quantity_on_hand
        old_cost = stock.avg_cost_per_unit_cents
        removed_qty = movement.quantity

        new_qty = old_qty - removed_qty

        # Recalculate average cost by reversing the purchase
        # If we're removing all quantity, set cost to 0
        new_avg_cost =
          if new_qty <= 0 do
            0
          else
            # Reverse the moving average calculation
            # old_avg = (old_qty * old_cost + purchase_qty * purchase_cost) / (old_qty + purchase_qty)
            # We need to solve for the previous avg_cost before this purchase
            # This is complex, so we'll use a simpler approach: if removing reduces to 0, set to 0
            # Otherwise, keep the current avg_cost (this is an approximation)
            # For exact reversal, we'd need to track the previous avg_cost, but for simplicity:
            if old_qty == removed_qty do
              0
            else
              # Approximate: keep current cost if we're not removing everything
              old_cost
            end
          end

        # Update stock
        stock
        |> InventoryItem.changeset(%{
          quantity_on_hand: max(new_qty, 0),
          avg_cost_per_unit_cents: new_avg_cost
        })
        |> Repo.update!()

        # Find and delete the related journal entry
        # Match by reference pattern and date to find the correct entry
        reference_pattern = "Purchase #{ingredient.code} @ #{location.code}"

        journal_entry =
          from(je in JournalEntry,
            where: je.reference == ^reference_pattern and je.entry_type == "inventory_purchase" and je.date == ^movement.movement_date
          )
          |> order_by([je], desc: je.inserted_at)
          |> limit(1)
          |> Repo.one()

        if journal_entry do
          Repo.delete!(journal_entry)
        end

        # Delete the movement
        Repo.delete!(movement)
      end)
    end
  end

  @doc """
  Update a purchase. Reverses the old purchase and creates a new one with updated values.
  """
  def update_purchase(movement_id, attrs) do
    movement = get_movement!(movement_id)

    if movement.movement_type != "purchase" do
      {:error, :not_a_purchase}
    else
      Repo.transaction(fn ->
        # Reverse the old purchase by directly reversing inventory
        ingredient = movement.ingredient
        location = movement.to_location
        stock = get_or_create_stock!(ingredient.id, location.id)

        old_qty = stock.quantity_on_hand
        removed_qty = movement.quantity
        new_qty = old_qty - removed_qty

        # Update stock
        stock
        |> InventoryItem.changeset(%{
          quantity_on_hand: max(new_qty, 0),
          avg_cost_per_unit_cents: if(new_qty <= 0, do: 0, else: stock.avg_cost_per_unit_cents)
        })
        |> Repo.update!()

        # Find and delete the related journal entry
        reference_pattern = "Purchase #{ingredient.code} @ #{location.code}"

        journal_entry =
          from(je in JournalEntry,
            where: je.reference == ^reference_pattern and je.entry_type == "inventory_purchase" and je.date == ^movement.movement_date
          )
          |> order_by([je], desc: je.inserted_at)
          |> limit(1)
          |> Repo.one()

        if journal_entry do
          Repo.delete!(journal_entry)
        end

        # Delete the old movement
        Repo.delete!(movement)

        # Create the new purchase with updated values
        case create_purchase(attrs) do
          {:ok, _result} -> :ok
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    end
  end

  # --- Transfer edit/delete helpers ---

  @doc """
  Delete a transfer movement. Reverses the inventory changes on both locations.
  """
  def delete_transfer(movement_id) do
    movement = get_movement!(movement_id)

    if movement.movement_type != "transfer" do
      {:error, :not_a_transfer}
    else
      Repo.transaction(fn ->
        ingredient = movement.ingredient
        from_location = movement.from_location
        to_location = movement.to_location
        transfer_qty = movement.quantity
        unit_cost_cents = movement.unit_cost_cents

        # Reverse: move quantity back from to_location to from_location
        from_stock = get_or_create_stock!(ingredient.id, from_location.id)
        to_stock = get_or_create_stock!(ingredient.id, to_location.id)

        # Remove from to_location
        old_to_qty = to_stock.quantity_on_hand
        old_to_cost = to_stock.avg_cost_per_unit_cents
        new_to_qty = old_to_qty - transfer_qty

        # Recalculate average cost for to_location (reverse the moving average)
        new_to_avg_cost =
          if new_to_qty <= 0 do
            0
          else
            # Reverse: if we're removing all transferred quantity, we need to recalculate
            # This is an approximation - for exact reversal we'd need to track previous costs
            if old_to_qty == transfer_qty do
              # If removing all, check if there was stock before
              0
            else
              # Approximate: keep current cost if we're not removing everything
              old_to_cost
            end
          end

        to_stock
        |> InventoryItem.changeset(%{
          quantity_on_hand: max(new_to_qty, 0),
          avg_cost_per_unit_cents: new_to_avg_cost
        })
        |> Repo.update!()

        # Add back to from_location
        old_from_qty = from_stock.quantity_on_hand
        old_from_cost = from_stock.avg_cost_per_unit_cents
        new_from_qty = old_from_qty + transfer_qty

        # Recalculate average cost for from_location
        new_from_avg_cost = calculate_weighted_avg_cost(old_from_qty, old_from_cost, transfer_qty, unit_cost_cents, new_from_qty)

        from_stock
        |> InventoryItem.changeset(%{
          quantity_on_hand: new_from_qty,
          avg_cost_per_unit_cents: new_from_avg_cost
        })
        |> Repo.update!()

        # Delete the movement
        Repo.delete!(movement)
      end)
    end
  end

  @doc """
  Update a transfer. Reverses the old transfer and creates a new one with updated values.
  """
  def update_transfer(movement_id, attrs) do
    movement = get_movement!(movement_id)

    if movement.movement_type != "transfer" do
      {:error, :not_a_transfer}
    else
      Repo.transaction(fn ->
        # Reverse the old transfer
        ingredient = movement.ingredient
        from_location = movement.from_location
        to_location = movement.to_location
        transfer_qty = movement.quantity
        unit_cost_cents = movement.unit_cost_cents

        from_stock = get_or_create_stock!(ingredient.id, from_location.id)
        to_stock = get_or_create_stock!(ingredient.id, to_location.id)

        # Remove from to_location
        old_to_qty = to_stock.quantity_on_hand
        new_to_qty = old_to_qty - transfer_qty

        to_stock
        |> InventoryItem.changeset(%{
          quantity_on_hand: max(new_to_qty, 0),
          avg_cost_per_unit_cents: if(new_to_qty <= 0, do: 0, else: to_stock.avg_cost_per_unit_cents)
        })
        |> Repo.update!()

        # Add back to from_location
        old_from_qty = from_stock.quantity_on_hand
        old_from_cost = from_stock.avg_cost_per_unit_cents
        new_from_qty = old_from_qty + transfer_qty

        new_from_avg_cost = calculate_weighted_avg_cost(old_from_qty, old_from_cost, transfer_qty, unit_cost_cents, new_from_qty)

        from_stock
        |> InventoryItem.changeset(%{
          quantity_on_hand: new_from_qty,
          avg_cost_per_unit_cents: new_from_avg_cost
        })
        |> Repo.update!()

        # Delete the old movement
        Repo.delete!(movement)

        # Create the new transfer with updated values
        case create_movement(attrs) do
          {:ok, _result} -> :ok
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    end
  end
end
