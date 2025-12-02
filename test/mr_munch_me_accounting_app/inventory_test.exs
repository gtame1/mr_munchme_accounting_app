defmodule MrMunchMeAccountingApp.InventoryTest do
  use MrMunchMeAccountingApp.DataCase, async: true

  import Ecto.Query

  alias MrMunchMeAccountingApp.{Inventory, Accounting, Repo}
  alias MrMunchMeAccountingApp.Inventory.{Ingredient, Location, InventoryItem, InventoryMovement}
  alias MrMunchMeAccountingApp.Accounting.JournalEntry

  setup do
    # Create accounts
    {:ok, cash_account} =
      Accounting.create_account(%{
        code: "1000",
        name: "Cash",
        type: "asset",
        normal_balance: "debit",
        is_cash: true
      })

    {:ok, ingredients_account} =
      Accounting.create_account(%{
        code: "1200",
        name: "Ingredients Inventory",
        type: "asset",
        normal_balance: "debit",
        is_cash: false
      })

    # Create ingredient
    {:ok, ingredient} =
      %Ingredient{}
      |> Ingredient.changeset(%{
        code: "FLOUR",
        name: "Flour",
        unit: "g"
      })
      |> Repo.insert()

    # Create locations
    {:ok, location} =
      %Location{}
      |> Location.changeset(%{
        code: "WAREHOUSE",
        name: "Warehouse"
      })
      |> Repo.insert()

    {:ok, from_location} =
      %Location{}
      |> Location.changeset(%{
        code: "KITCHEN",
        name: "Kitchen"
      })
      |> Repo.insert()

    {
      :ok,
      cash_account: cash_account,
      ingredients_account: ingredients_account,
      ingredient: ingredient,
      location: location,
      from_location: from_location
    }
  end

  describe "delete_purchase/1" do
    test "successfully deletes a purchase and reverses inventory changes", %{
      cash_account: cash_account,
      ingredient: ingredient,
      location: location
    } do
      # Create a purchase
      purchase_attrs = %{
        "ingredient_code" => ingredient.code,
        "location_code" => location.code,
        "quantity" => 1000,
        "total_cost_pesos" => "50.00",
        "paid_from_account_id" => to_string(cash_account.id),
        "purchase_date" => Date.utc_today()
      }

      assert {:ok, _} = Inventory.create_purchase(purchase_attrs)

      # Verify stock was created
      stock = Inventory.get_or_create_stock!(ingredient.id, location.id)
      assert stock.quantity_on_hand == 1000
      # 50.00 pesos = 5000 cents, 5000 / 1000 = 5 cents per unit
      assert stock.avg_cost_per_unit_cents == 5

      # Get the movement
      movement =
        Repo.one(
          from m in InventoryMovement,
            where: m.movement_type == "purchase" and m.ingredient_id == ^ingredient.id,
            order_by: [desc: m.inserted_at],
            limit: 1
        )

      # Verify journal entry was created
      journal_entry =
        Repo.one(
          from je in JournalEntry,
            where: je.entry_type == "inventory_purchase",
            order_by: [desc: je.inserted_at],
            limit: 1
        )

      assert journal_entry != nil

      # Delete the purchase
      assert {:ok, _} = Inventory.delete_purchase(movement.id)

      # Verify movement is deleted
      refute Repo.get(InventoryMovement, movement.id)

      # Verify inventory was reversed
      stock = Repo.get(InventoryItem, stock.id)
      assert stock.quantity_on_hand == 0
      assert stock.avg_cost_per_unit_cents == 0

      # Verify journal entry was deleted
      refute Repo.get(JournalEntry, journal_entry.id)
    end

    test "reverses inventory correctly when there was existing stock", %{
      cash_account: cash_account,
      ingredient: ingredient,
      location: location
    } do
      # Create first purchase
      purchase1_attrs = %{
        "ingredient_code" => ingredient.code,
        "location_code" => location.code,
        "quantity" => 1000,
        "total_cost_pesos" => "50.00",
        "paid_from_account_id" => to_string(cash_account.id),
        "purchase_date" => Date.utc_today()
      }

      assert {:ok, _} = Inventory.create_purchase(purchase1_attrs)

      # Create second purchase
      purchase2_attrs = %{
        "ingredient_code" => ingredient.code,
        "location_code" => location.code,
        "quantity" => 500,
        "total_cost_pesos" => "30.00",
        "paid_from_account_id" => to_string(cash_account.id),
        "purchase_date" => Date.utc_today()
      }

      assert {:ok, _} = Inventory.create_purchase(purchase2_attrs)

      # Verify stock after both purchases
      stock = Inventory.get_or_create_stock!(ingredient.id, location.id)
      assert stock.quantity_on_hand == 1500
      # Average cost: (1000 * 5 + 500 * 6) / 1500 = 5333 / 1500 = 3.55... cents
      # First purchase: 50.00 pesos = 5000 cents / 1000 = 5 cents per unit
      # Second purchase: 30.00 pesos = 3000 cents / 500 = 6 cents per unit
      # Weighted average: (1000 * 5 + 500 * 6) / 1500 = 8000 / 1500 = 5.33... cents
      expected_avg = div(1000 * 5 + 500 * 6, 1500)
      assert stock.avg_cost_per_unit_cents == expected_avg

      # Get the second movement by filtering for the one with 500 quantity
      # (30.00 pesos = 3000 cents total)
      second_movement =
        Repo.one!(
          from m in InventoryMovement,
            where: m.movement_type == "purchase" and m.ingredient_id == ^ingredient.id and m.quantity == 500
        )

      # Verify it's the correct one (500 units, 30.00 pesos = 3000 cents)
      assert second_movement.quantity == 500
      assert second_movement.total_cost_cents == 3000

      # Delete the second purchase
      assert {:ok, _} = Inventory.delete_purchase(second_movement.id)

      # Verify inventory was reversed to first purchase state
      stock = Repo.get(InventoryItem, stock.id)
      assert stock.quantity_on_hand == 1000
      # Should approximate the original cost (5 cents per unit)
      # The delete function uses an approximation, so we allow some variance
      assert stock.avg_cost_per_unit_cents in [5, 4, 6] # Allow small rounding differences
    end

    test "returns error when trying to delete a non-purchase movement", %{
      cash_account: cash_account,
      ingredient: ingredient,
      from_location: from_location,
      location: location
    } do
      # First create stock in from_location
      purchase_attrs = %{
        "ingredient_code" => ingredient.code,
        "location_code" => from_location.code,
        "quantity" => 1000,
        "total_cost_pesos" => "50.00",
        "paid_from_account_id" => to_string(cash_account.id),
        "purchase_date" => Date.utc_today()
      }

      assert {:ok, _} = Inventory.create_purchase(purchase_attrs)

      # Create a transfer
      {:ok, _} =
        Inventory.create_movement(%{
          "movement_type" => "transfer",
          "ingredient_code" => ingredient.code,
          "from_location_code" => from_location.code,
          "to_location_code" => location.code,
          "quantity" => 500,
          "movement_date" => Date.utc_today()
        })

      movement =
        Repo.one(
          from m in InventoryMovement,
            where: m.movement_type == "transfer" and m.ingredient_id == ^ingredient.id,
            order_by: [desc: m.inserted_at],
            limit: 1
        )

      # Try to delete it as a purchase
      assert {:error, :not_a_purchase} = Inventory.delete_purchase(movement.id)

      # Verify movement still exists
      assert Repo.get(InventoryMovement, movement.id)
    end
  end

  describe "delete_transfer/1" do
    test "successfully deletes a transfer and reverses inventory changes", %{
      cash_account: cash_account,
      ingredient: ingredient,
      from_location: from_location,
      location: location
    } do
      # First create stock in from_location
      purchase_attrs = %{
        "ingredient_code" => ingredient.code,
        "location_code" => from_location.code,
        "quantity" => 1000,
        "total_cost_pesos" => "50.00",
        "paid_from_account_id" => to_string(cash_account.id),
        "purchase_date" => Date.utc_today()
      }

      assert {:ok, _} = Inventory.create_purchase(purchase_attrs)

      # Create a transfer
      {:ok, _} =
        Inventory.create_movement(%{
          "movement_type" => "transfer",
          "ingredient_code" => ingredient.code,
          "from_location_code" => from_location.code,
          "to_location_code" => location.code,
          "quantity" => 500,
          "movement_date" => Date.utc_today()
        })

      # Verify stock after transfer
      from_stock = Inventory.get_or_create_stock!(ingredient.id, from_location.id)
      to_stock = Inventory.get_or_create_stock!(ingredient.id, location.id)
      assert from_stock.quantity_on_hand == 500
      assert to_stock.quantity_on_hand == 500

      # Get the transfer movement
      movement =
        Repo.one(
          from m in InventoryMovement,
            where: m.movement_type == "transfer" and m.ingredient_id == ^ingredient.id,
            order_by: [desc: m.inserted_at],
            limit: 1
        )

      # Delete the transfer
      assert {:ok, _} = Inventory.delete_transfer(movement.id)

      # Verify movement is deleted
      refute Repo.get(InventoryMovement, movement.id)

      # Verify inventory was reversed
      from_stock = Repo.get(InventoryItem, from_stock.id)
      to_stock = Repo.get(InventoryItem, to_stock.id)
      assert from_stock.quantity_on_hand == 1000
      assert to_stock.quantity_on_hand == 0
    end

    test "returns error when trying to delete a non-transfer movement", %{
      cash_account: cash_account,
      ingredient: ingredient,
      location: location
    } do
      # Create a purchase
      purchase_attrs = %{
        "ingredient_code" => ingredient.code,
        "location_code" => location.code,
        "quantity" => 1000,
        "total_cost_pesos" => "50.00",
        "paid_from_account_id" => to_string(cash_account.id),
        "purchase_date" => Date.utc_today()
      }

      assert {:ok, _} = Inventory.create_purchase(purchase_attrs)

      movement =
        Repo.one(
          from m in InventoryMovement,
            where: m.movement_type == "purchase" and m.ingredient_id == ^ingredient.id,
            order_by: [desc: m.inserted_at],
            limit: 1
        )

      # Try to delete it as a transfer
      assert {:error, :not_a_transfer} = Inventory.delete_transfer(movement.id)

      # Verify movement still exists
      assert Repo.get(InventoryMovement, movement.id)
    end
  end
end
