defmodule MrMunchMeAccountingApp.Inventory.VerificationTest do
  use MrMunchMeAccountingApp.DataCase, async: true

  alias MrMunchMeAccountingApp.{Accounting, Inventory, Repo}
  alias MrMunchMeAccountingApp.Inventory.{Ingredient, Location, InventoryItem, InventoryMovement, Verification}

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

    {:ok, wip_account} =
      Accounting.create_account(%{
        code: "1220",
        name: "Ingredients Inventory (WIP)",
        type: "asset",
        normal_balance: "debit",
        is_cash: false
      })

    {:ok, _cogs_account} =
      Accounting.create_account(%{
        code: "5000",
        name: "Ingredients COGS",
        type: "expense",
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

    # Create location
    {:ok, location} =
      %Location{}
      |> Location.changeset(%{
        code: "WAREHOUSE",
        name: "Warehouse"
      })
      |> Repo.insert()

    {
      :ok,
      cash_account: cash_account,
      ingredients_account: ingredients_account,
      wip_account: wip_account,
      ingredient: ingredient,
      location: location
    }
  end

  describe "verify_inventory_quantities/0" do
    test "returns ok when quantities match", %{
      cash_account: cash_account,
      ingredient: ingredient,
      location: location
    } do
      # Create a purchase
      {:ok, _} =
        Inventory.create_purchase(%{
          "ingredient_code" => ingredient.code,
          "location_code" => location.code,
          "quantity" => 1000,
          "total_cost_pesos" => "50.00",
          "paid_from_account_id" => to_string(cash_account.id),
          "purchase_date" => Date.utc_today()
        })

      # Create a usage
      {:ok, _} =
        Inventory.create_movement(%{
          "movement_type" => "usage",
          "ingredient_code" => ingredient.code,
          "from_location_code" => location.code,
          "quantity" => 200,
          "movement_date" => Date.utc_today()
        })

      # Verify quantities
      assert {:ok, %{checked_items: _}} = Verification.verify_inventory_quantities()
    end

    test "returns error when quantities don't match", %{
      cash_account: cash_account,
      ingredient: ingredient,
      location: location
    } do
      # Create a purchase
      {:ok, _} =
        Inventory.create_purchase(%{
          "ingredient_code" => ingredient.code,
          "location_code" => location.code,
          "quantity" => 1000,
          "total_cost_pesos" => "50.00",
          "paid_from_account_id" => to_string(cash_account.id),
          "purchase_date" => Date.utc_today()
        })

      # Manually corrupt the inventory item
      stock = Inventory.get_or_create_stock!(ingredient.id, location.id)
      stock
      |> InventoryItem.changeset(%{quantity_on_hand: 9999})
      |> Repo.update!()

      # Verify quantities - should find mismatch
      assert {:error, issues} = Verification.verify_inventory_quantities()
      assert length(issues) > 0
      assert Enum.any?(issues, fn issue -> String.contains?(issue, "System: 9999") end)
    end
  end

  describe "verify_wip_balance/0" do
    test "returns ok when WIP balance matches calculated value", %{
      wip_account: wip_account
    } do
      # Initially, WIP should be 0
      assert {:ok, %{wip_balance: balance}} = Verification.verify_wip_balance()
      assert balance == 0
    end

    test "returns ok when WIP balance matches", %{
      wip_account: wip_account,
      ingredients_account: ingredients_account
    } do
      # Create a proper balanced order_in_prep entry
      {:ok, _entry} =
        Accounting.create_journal_entry(%{
          "date" => Date.utc_today(),
          "description" => "Test WIP entry",
          "entry_type" => "order_in_prep",
          "reference" => "Order #999",
          "journal_lines" => [
            %{"account_id" => wip_account.id, "debit_cents" => 10000},
            %{"account_id" => ingredients_account.id, "credit_cents" => 10000}
          ]
        })

      # The verification should pass with a balanced entry
      result = Verification.verify_wip_balance()
      assert match?({:ok, _}, result)
    end
  end

  describe "verify_inventory_cost_accounting/0" do
    test "returns ok when inventory value matches account balance", %{
      cash_account: cash_account,
      ingredient: ingredient,
      location: location
    } do
      # Create a purchase
      {:ok, _} =
        Inventory.create_purchase(%{
          "ingredient_code" => ingredient.code,
          "location_code" => location.code,
          "quantity" => 1000,
          "total_cost_pesos" => "50.00",
          "paid_from_account_id" => to_string(cash_account.id),
          "purchase_date" => Date.utc_today()
        })

      # Verify cost accounting
      result = Verification.verify_inventory_cost_accounting()
      assert match?({:ok, _}, result)
    end
  end

  describe "verify_order_wip_consistency/0" do
    test "returns ok when all orders have consistent WIP entries", %{
      wip_account: wip_account
    } do
      # With no orders, should be ok
      assert {:ok, %{checked_orders: 0}} = Verification.verify_order_wip_consistency()
    end
  end

  describe "verify_journal_entries_balanced/0" do
    test "returns ok when all journal entries are balanced", %{
      cash_account: cash_account,
      ingredients_account: ingredients_account
    } do
      # Create a balanced entry
      {:ok, _} =
        Accounting.create_journal_entry(%{
          "date" => Date.utc_today(),
          "description" => "Test entry",
          "entry_type" => "other",
          "journal_lines" => [
            %{"account_id" => cash_account.id, "debit_cents" => 10000},
            %{"account_id" => ingredients_account.id, "credit_cents" => 10000}
          ]
        })

      # Verify all entries are balanced
      result = Verification.verify_journal_entries_balanced()
      assert match?({:ok, _}, result)
    end
  end

  describe "run_all_checks/0" do
    test "runs all verification checks", %{
      cash_account: cash_account,
      ingredient: ingredient,
      location: location
    } do
      # Create some inventory to test with
      {:ok, _} =
        Inventory.create_purchase(%{
          "ingredient_code" => ingredient.code,
          "location_code" => location.code,
          "quantity" => 1000,
          "total_cost_pesos" => "50.00",
          "paid_from_account_id" => to_string(cash_account.id),
          "purchase_date" => Date.utc_today()
        })

      # Run all checks
      results = Verification.run_all_checks()

      # Verify we got results for all checks
      assert Map.has_key?(results, :inventory_quantities)
      assert Map.has_key?(results, :wip_balance)
      assert Map.has_key?(results, :inventory_cost_accounting)
      assert Map.has_key?(results, :order_wip_consistency)
      assert Map.has_key?(results, :journal_entries_balanced)

      # All should pass in a clean test environment
      Enum.each(results, fn {_check_name, result} ->
        assert match?({:ok, _}, result)
      end)
    end
  end
end
