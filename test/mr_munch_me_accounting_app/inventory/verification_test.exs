defmodule MrMunchMeAccountingApp.Inventory.VerificationTest do
  use MrMunchMeAccountingApp.DataCase, async: true

  alias MrMunchMeAccountingApp.{Accounting, Inventory, Repo}
  alias MrMunchMeAccountingApp.Inventory.{Ingredient, Location, InventoryItem, InventoryMovement, Verification}
  alias MrMunchMeAccountingApp.Orders.Order

  # Get or create an account, handling the case where it already exists
  # (can happen with async tests sharing the database)
  defp get_or_create_account!(attrs) do
    case Accounting.get_account_by_code(attrs.code) do
      nil ->
        {:ok, account} = Accounting.create_account(attrs)
        account
      existing ->
        existing
    end
  end

  setup do
    # Create accounts needed by verification checks (get-or-create to handle async conflicts)
    cash_account = get_or_create_account!(%{code: "1000", name: "Cash", type: "asset", normal_balance: "debit", is_cash: true})
    ar_account = get_or_create_account!(%{code: "1100", name: "Accounts Receivable", type: "asset", normal_balance: "debit", is_cash: false})
    ingredients_account = get_or_create_account!(%{code: "1200", name: "Ingredients Inventory", type: "asset", normal_balance: "debit", is_cash: false})
    wip_account = get_or_create_account!(%{code: "1220", name: "WIP Inventory", type: "asset", normal_balance: "debit", is_cash: false})
    customer_deposits_account = get_or_create_account!(%{code: "2200", name: "Customer Deposits", type: "liability", normal_balance: "credit", is_cash: false})
    owners_equity_account = get_or_create_account!(%{code: "3000", name: "Owner's Equity", type: "equity", normal_balance: "credit", is_cash: false})
    owners_drawings_account = get_or_create_account!(%{code: "3100", name: "Owner's Drawings", type: "equity", normal_balance: "debit", is_cash: false})
    sales_account = get_or_create_account!(%{code: "4000", name: "Sales Revenue", type: "revenue", normal_balance: "credit", is_cash: false})
    gift_contributions_account = get_or_create_account!(%{code: "4100", name: "Gift Contributions", type: "revenue", normal_balance: "credit", is_cash: false})
    cogs_account = get_or_create_account!(%{code: "5000", name: "Ingredients COGS", type: "expense", normal_balance: "debit", is_cash: false})
    waste_account = get_or_create_account!(%{code: "6060", name: "Inventory Waste & Shrinkage", type: "expense", normal_balance: "debit", is_cash: false})
    samples_gifts_account = get_or_create_account!(%{code: "6070", name: "Samples & Gifts", type: "expense", normal_balance: "debit", is_cash: false})

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
      ar_account: ar_account,
      ingredients_account: ingredients_account,
      wip_account: wip_account,
      customer_deposits_account: customer_deposits_account,
      owners_equity_account: owners_equity_account,
      owners_drawings_account: owners_drawings_account,
      sales_account: sales_account,
      gift_contributions_account: gift_contributions_account,
      cogs_account: cogs_account,
      waste_account: waste_account,
      samples_gifts_account: samples_gifts_account,
      ingredient: ingredient,
      location: location
    }
  end

  # ── verify_inventory_quantities ─────────────────────────────────────────

  describe "verify_inventory_quantities/0" do
    test "returns ok when quantities match", %{
      cash_account: cash_account,
      ingredient: ingredient,
      location: location
    } do
      {:ok, _} =
        Inventory.create_purchase(%{
          "ingredient_code" => ingredient.code,
          "location_code" => location.code,
          "quantity" => 1000,
          "total_cost_pesos" => "50.00",
          "paid_from_account_id" => to_string(cash_account.id),
          "purchase_date" => Date.utc_today()
        })

      {:ok, _} =
        Inventory.create_movement(%{
          "movement_type" => "usage",
          "ingredient_code" => ingredient.code,
          "from_location_code" => location.code,
          "quantity" => 200,
          "movement_date" => Date.utc_today()
        })

      assert {:ok, %{checked_items: _}} = Verification.verify_inventory_quantities()
    end

    test "returns error when quantities don't match", %{
      cash_account: cash_account,
      ingredient: ingredient,
      location: location
    } do
      {:ok, _} =
        Inventory.create_purchase(%{
          "ingredient_code" => ingredient.code,
          "location_code" => location.code,
          "quantity" => 1000,
          "total_cost_pesos" => "50.00",
          "paid_from_account_id" => to_string(cash_account.id),
          "purchase_date" => Date.utc_today()
        })

      stock = Inventory.get_or_create_stock!(ingredient.id, location.id)
      stock
      |> InventoryItem.changeset(%{quantity_on_hand: 9999})
      |> Repo.update!()

      assert {:error, issues} = Verification.verify_inventory_quantities()
      assert length(issues) > 0
      assert Enum.any?(issues, fn issue -> String.contains?(issue, "System: 9999") end)
    end
  end

  # ── verify_wip_balance ─────────────────────────────────────────────────

  describe "verify_wip_balance/0" do
    test "returns ok when WIP balance matches calculated value" do
      assert {:ok, %{wip_balance: balance}} = Verification.verify_wip_balance()
      assert balance == 0
    end

    test "returns ok when WIP balance matches", %{
      wip_account: wip_account,
      ingredients_account: ingredients_account
    } do
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

      result = Verification.verify_wip_balance()
      assert match?({:ok, _}, result)
    end
  end

  # ── verify_inventory_cost_accounting ────────────────────────────────────

  describe "verify_inventory_cost_accounting/0" do
    test "returns ok when inventory value matches account balance", %{
      cash_account: cash_account,
      ingredient: ingredient,
      location: location
    } do
      {:ok, _} =
        Inventory.create_purchase(%{
          "ingredient_code" => ingredient.code,
          "location_code" => location.code,
          "quantity" => 1000,
          "total_cost_pesos" => "50.00",
          "paid_from_account_id" => to_string(cash_account.id),
          "purchase_date" => Date.utc_today()
        })

      result = Verification.verify_inventory_cost_accounting()
      assert match?({:ok, _}, result)
    end

    test "returns error when inventory value doesn't match account balance", %{
      cash_account: cash_account,
      ingredients_account: ingredients_account,
      ingredient: ingredient,
      location: location
    } do
      {:ok, _} =
        Inventory.create_purchase(%{
          "ingredient_code" => ingredient.code,
          "location_code" => location.code,
          "quantity" => 1000,
          "total_cost_pesos" => "50.00",
          "paid_from_account_id" => to_string(cash_account.id),
          "purchase_date" => Date.utc_today()
        })

      # Create an extra debit to account 1200 that doesn't correspond to inventory
      {:ok, _} =
        Accounting.create_journal_entry(%{
          "date" => Date.utc_today(),
          "description" => "Phantom entry",
          "entry_type" => "other",
          "journal_lines" => [
            %{"account_id" => ingredients_account.id, "debit_cents" => 50000},
            %{"account_id" => cash_account.id, "credit_cents" => 50000}
          ]
        })

      assert {:error, _issues} = Verification.verify_inventory_cost_accounting()
    end
  end

  # ── verify_order_wip_consistency ────────────────────────────────────────

  describe "verify_order_wip_consistency/0" do
    test "returns ok when no orders exist" do
      assert {:ok, %{checked_orders: 0}} = Verification.verify_order_wip_consistency()
    end
  end

  # ── verify_journal_entries_balanced ─────────────────────────────────────

  describe "verify_journal_entries_balanced/0" do
    test "returns ok when all journal entries are balanced", %{
      cash_account: cash_account,
      ingredients_account: ingredients_account
    } do
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

      result = Verification.verify_journal_entries_balanced()
      assert match?({:ok, _}, result)
    end
  end

  # ── verify_withdrawal_accounts ─────────────────────────────────────────

  describe "verify_withdrawal_accounts/0" do
    test "returns ok when no withdrawals debit Owner's Equity", %{
      owners_drawings_account: owners_drawings_account,
      cash_account: cash_account
    } do
      # Create a correct withdrawal (debits Owner's Drawings 3100)
      {:ok, _} =
        Accounting.create_journal_entry(%{
          "date" => Date.utc_today(),
          "description" => "Correct withdrawal",
          "entry_type" => "withdrawal",
          "reference" => "Withdrawal #1",
          "journal_lines" => [
            %{"account_id" => owners_drawings_account.id, "debit_cents" => 5000},
            %{"account_id" => cash_account.id, "credit_cents" => 5000}
          ]
        })

      assert {:ok, %{checked: "all withdrawals", issues: 0}} = Verification.verify_withdrawal_accounts()
    end

    test "returns error when withdrawal debits Owner's Equity instead of Drawings", %{
      owners_equity_account: owners_equity_account,
      cash_account: cash_account
    } do
      # Create an incorrect withdrawal (debits Owner's Equity 3000 instead of 3100)
      {:ok, _} =
        Accounting.create_journal_entry(%{
          "date" => Date.utc_today(),
          "description" => "Incorrect withdrawal",
          "entry_type" => "withdrawal",
          "reference" => "Withdrawal #2",
          "journal_lines" => [
            %{"account_id" => owners_equity_account.id, "debit_cents" => 8000},
            %{"account_id" => cash_account.id, "credit_cents" => 8000}
          ]
        })

      assert {:error, issues} = Verification.verify_withdrawal_accounts()
      assert length(issues) > 0
      assert Enum.any?(issues, fn issue -> String.contains?(issue, "incorrectly debiting") end)
    end
  end

  # ── verify_duplicate_cogs_entries ──────────────────────────────────────

  describe "verify_duplicate_cogs_entries/0" do
    test "returns ok when no duplicates exist", %{
      wip_account: wip_account,
      ingredients_account: ingredients_account
    } do
      # Create a single order_in_prep entry
      {:ok, _} =
        Accounting.create_journal_entry(%{
          "date" => Date.utc_today(),
          "description" => "Order in prep",
          "entry_type" => "order_in_prep",
          "reference" => "Order #100",
          "journal_lines" => [
            %{"account_id" => wip_account.id, "debit_cents" => 5000},
            %{"account_id" => ingredients_account.id, "credit_cents" => 5000}
          ]
        })

      assert {:ok, %{duplicate_groups: 0}} = Verification.verify_duplicate_cogs_entries()
    end

    test "returns error when duplicate entries exist for same reference", %{
      wip_account: wip_account,
      ingredients_account: ingredients_account
    } do
      # Create two order_in_prep entries with the same reference
      {:ok, _} =
        Accounting.create_journal_entry(%{
          "date" => Date.utc_today(),
          "description" => "Order in prep",
          "entry_type" => "order_in_prep",
          "reference" => "Order #200",
          "journal_lines" => [
            %{"account_id" => wip_account.id, "debit_cents" => 5000},
            %{"account_id" => ingredients_account.id, "credit_cents" => 5000}
          ]
        })

      {:ok, _} =
        Accounting.create_journal_entry(%{
          "date" => Date.utc_today(),
          "description" => "Order in prep (duplicate)",
          "entry_type" => "order_in_prep",
          "reference" => "Order #200",
          "journal_lines" => [
            %{"account_id" => wip_account.id, "debit_cents" => 5000},
            %{"account_id" => ingredients_account.id, "credit_cents" => 5000}
          ]
        })

      assert {:error, issues} = Verification.verify_duplicate_cogs_entries()
      assert length(issues) > 0
      assert Enum.any?(issues, fn issue -> String.contains?(issue, "Order #200") end)
    end
  end

  # ── verify_gift_order_accounting ───────────────────────────────────────

  describe "verify_gift_order_accounting/0" do
    test "returns ok when no gift orders exist" do
      assert {:ok, %{checked: 0, issues: 0}} = Verification.verify_gift_order_accounting()
    end

    test "returns ok when gift order has proper gift accounting", %{
      wip_account: wip_account,
      samples_gifts_account: samples_gifts_account,
      location: location
    } do
      product = create_product()
      order = create_gift_order(product, location, "delivered")

      # Create a proper gift delivery entry with 6070 line
      {:ok, _} =
        Accounting.create_journal_entry(%{
          "date" => Date.utc_today(),
          "description" => "Gift order delivered",
          "entry_type" => "order_delivered",
          "reference" => "Order ##{order.id}",
          "journal_lines" => [
            %{"account_id" => samples_gifts_account.id, "debit_cents" => 3000},
            %{"account_id" => wip_account.id, "credit_cents" => 3000}
          ]
        })

      assert {:ok, %{checked: 1, issues: 0}} = Verification.verify_gift_order_accounting()
    end

    test "returns error when gift order has sale-style accounting", %{
      wip_account: wip_account,
      cogs_account: cogs_account,
      location: location
    } do
      product = create_product()
      order = create_gift_order(product, location, "delivered")

      # Create a sale-style delivery entry (no 6070 line)
      {:ok, _} =
        Accounting.create_journal_entry(%{
          "date" => Date.utc_today(),
          "description" => "Order delivered (sale style)",
          "entry_type" => "order_delivered",
          "reference" => "Order ##{order.id}",
          "journal_lines" => [
            %{"account_id" => cogs_account.id, "debit_cents" => 3000},
            %{"account_id" => wip_account.id, "credit_cents" => 3000}
          ]
        })

      assert {:error, issues} = Verification.verify_gift_order_accounting()
      assert Enum.any?(issues, fn issue -> String.contains?(issue, "sale-style") end)
    end

    test "returns ok when gift order was corrected with a separate entry", %{
      wip_account: wip_account,
      cogs_account: cogs_account,
      samples_gifts_account: samples_gifts_account,
      location: location
    } do
      product = create_product()
      order = create_gift_order(product, location, "delivered")

      # Create original sale-style entry
      {:ok, _} =
        Accounting.create_journal_entry(%{
          "date" => Date.utc_today(),
          "description" => "Order delivered (sale style)",
          "entry_type" => "order_delivered",
          "reference" => "Order ##{order.id}",
          "journal_lines" => [
            %{"account_id" => cogs_account.id, "debit_cents" => 3000},
            %{"account_id" => wip_account.id, "credit_cents" => 3000}
          ]
        })

      # Create correction entry with 6070 line (same reference, different type)
      {:ok, _} =
        Accounting.create_journal_entry(%{
          "date" => Date.utc_today(),
          "description" => "Correction: gift order",
          "entry_type" => "other",
          "reference" => "Order ##{order.id}",
          "journal_lines" => [
            %{"account_id" => wip_account.id, "debit_cents" => 3000},
            %{"account_id" => cogs_account.id, "credit_cents" => 3000},
            %{"account_id" => samples_gifts_account.id, "debit_cents" => 3000},
            %{"account_id" => wip_account.id, "credit_cents" => 3000}
          ]
        })

      # Should pass because a correction entry with 6070 exists
      assert {:ok, %{checked: 1, issues: 0}} = Verification.verify_gift_order_accounting()
    end
  end

  # ── verify_movement_costs ──────────────────────────────────────────────

  describe "verify_movement_costs/0" do
    test "returns ok when no zero-cost movements exist" do
      assert {:ok, %{checked: "all movements", zero_cost: 0}} = Verification.verify_movement_costs()
    end

    test "returns error when usage movements have $0 cost", %{
      ingredient: ingredient,
      location: location,
      cash_account: cash_account
    } do
      # Create a purchase first (so we have stock)
      {:ok, _} =
        Inventory.create_purchase(%{
          "ingredient_code" => ingredient.code,
          "location_code" => location.code,
          "quantity" => 1000,
          "total_cost_pesos" => "50.00",
          "paid_from_account_id" => to_string(cash_account.id),
          "purchase_date" => Date.utc_today()
        })

      # Directly insert a zero-cost usage movement
      {:ok, _} =
        %InventoryMovement{}
        |> InventoryMovement.changeset(%{
          movement_type: "usage",
          ingredient_id: ingredient.id,
          from_location_id: location.id,
          quantity: 100,
          unit_cost_cents: 0,
          total_cost_cents: 0,
          movement_date: Date.utc_today()
        })
        |> Repo.insert()

      assert {:error, issues} = Verification.verify_movement_costs()
      assert Enum.any?(issues, fn issue -> String.contains?(issue, "$0 cost") end)
    end
  end

  # ── repair_inventory_quantities ────────────────────────────────────────

  describe "repair_inventory_quantities/0" do
    test "fixes corrupted quantities", %{
      cash_account: cash_account,
      ingredient: ingredient,
      location: location
    } do
      {:ok, _} =
        Inventory.create_purchase(%{
          "ingredient_code" => ingredient.code,
          "location_code" => location.code,
          "quantity" => 500,
          "total_cost_pesos" => "25.00",
          "paid_from_account_id" => to_string(cash_account.id),
          "purchase_date" => Date.utc_today()
        })

      # Corrupt the quantity
      stock = Inventory.get_or_create_stock!(ingredient.id, location.id)
      stock |> InventoryItem.changeset(%{quantity_on_hand: 9999}) |> Repo.update!()

      # Verify it's broken
      assert {:error, _} = Verification.verify_inventory_quantities()

      # Repair
      assert {:ok, repairs} = Verification.repair_inventory_quantities()
      assert length(repairs) > 0

      # Verify it's now fixed
      assert {:ok, _} = Verification.verify_inventory_quantities()
    end
  end

  # ── repair_inventory_cost_accounting ───────────────────────────────────

  describe "repair_inventory_cost_accounting/0" do
    test "creates adjusting entry when account balance doesn't match inventory value", %{
      cash_account: cash_account,
      ingredients_account: ingredients_account,
      ingredient: ingredient,
      location: location
    } do
      {:ok, _} =
        Inventory.create_purchase(%{
          "ingredient_code" => ingredient.code,
          "location_code" => location.code,
          "quantity" => 1000,
          "total_cost_pesos" => "50.00",
          "paid_from_account_id" => to_string(cash_account.id),
          "purchase_date" => Date.utc_today()
        })

      # Add phantom debit to inventory account (creates mismatch > 100 cents)
      {:ok, _} =
        Accounting.create_journal_entry(%{
          "date" => Date.utc_today(),
          "description" => "Phantom entry",
          "entry_type" => "other",
          "journal_lines" => [
            %{"account_id" => ingredients_account.id, "debit_cents" => 50000},
            %{"account_id" => cash_account.id, "credit_cents" => 50000}
          ]
        })

      # Verify it's broken
      assert {:error, _} = Verification.verify_inventory_cost_accounting()

      # Repair — should include step 1 (dedup, nothing to fix) and step 2 (shrinkage adjustment)
      assert {:ok, results} = Verification.repair_inventory_cost_accounting()

      step1 = Enum.find(results, fn r -> r[:step] == "1. Duplicate cleanup" end)
      assert step1 != nil
      assert step1.duplicates_removed == 0

      shrinkage = Enum.find(results, fn r -> r[:step] == "2. Shrinkage adjustment" end)
      assert shrinkage != nil
      assert shrinkage.action =~ "Created adjusting entry"

      # Verify it's now fixed
      assert {:ok, _} = Verification.verify_inventory_cost_accounting()
    end

    test "returns empty list when difference is within tolerance", %{
      cash_account: cash_account,
      ingredient: ingredient,
      location: location
    } do
      {:ok, _} =
        Inventory.create_purchase(%{
          "ingredient_code" => ingredient.code,
          "location_code" => location.code,
          "quantity" => 1000,
          "total_cost_pesos" => "50.00",
          "paid_from_account_id" => to_string(cash_account.id),
          "purchase_date" => Date.utc_today()
        })

      # No mismatch, should return empty repairs
      assert {:ok, []} = Verification.repair_inventory_cost_accounting()
    end

    test "dedup fixes mismatch without needing shrinkage entry", %{
      cash_account: cash_account,
      wip_account: wip_account,
      ingredients_account: ingredients_account,
      ingredient: ingredient,
      location: location
    } do
      # Purchase: 1000g flour at $50 (5000 cents) → inventory_value=5000, acct_balance=5000
      {:ok, _} =
        Inventory.create_purchase(%{
          "ingredient_code" => ingredient.code,
          "location_code" => location.code,
          "quantity" => 1000,
          "total_cost_pesos" => "50.00",
          "paid_from_account_id" => to_string(cash_account.id),
          "purchase_date" => Date.utc_today()
        })

      # Simulate order consuming 400g: reduce inventory qty to match what
      # one order_in_prep entry would credit from account 1200
      # avg_cost = 5 cents/g, 400g = 2000 cents
      stock = Inventory.get_or_create_stock!(ingredient.id, location.id)
      stock |> InventoryItem.changeset(%{quantity_on_hand: 600}) |> Repo.update!()
      # Now inventory_value = 600 × 5 = 3000

      # Create one legitimate order_in_prep + one duplicate
      # Each credits 1200 by 2000 cents
      {:ok, _} =
        Accounting.create_journal_entry(%{
          "date" => Date.utc_today(),
          "description" => "Order in prep",
          "entry_type" => "order_in_prep",
          "reference" => "Order #500",
          "journal_lines" => [
            %{"account_id" => wip_account.id, "debit_cents" => 2000},
            %{"account_id" => ingredients_account.id, "credit_cents" => 2000}
          ]
        })

      {:ok, _} =
        Accounting.create_journal_entry(%{
          "date" => Date.utc_today(),
          "description" => "Order in prep (duplicate)",
          "entry_type" => "order_in_prep",
          "reference" => "Order #500",
          "journal_lines" => [
            %{"account_id" => wip_account.id, "debit_cents" => 2000},
            %{"account_id" => ingredients_account.id, "credit_cents" => 2000}
          ]
        })

      # inventory_value=3000, acct_balance=5000-2000-2000=1000 → diff=2000, broken
      assert {:error, _} = Verification.verify_inventory_cost_accounting()

      # Repair: dedup removes the duplicate → acct_balance=5000-2000=3000=inventory_value
      assert {:ok, results} = Verification.repair_inventory_cost_accounting()

      # Should have dedup step report
      step1 = Enum.find(results, fn r -> r[:step] == "1. Duplicate cleanup" end)
      assert step1 != nil
      assert step1.duplicates_removed >= 1

      # Should NOT have a shrinkage adjustment (dedup was enough)
      step2 = Enum.find(results, fn r -> r[:step] == "2. Shrinkage adjustment" end)
      assert step2 == nil

      # Should now be clean
      assert {:ok, _} = Verification.verify_inventory_cost_accounting()
    end

    test "dedup partially fixes mismatch, shrinkage covers remainder", %{
      cash_account: cash_account,
      wip_account: wip_account,
      ingredients_account: ingredients_account,
      ingredient: ingredient,
      location: location
    } do
      {:ok, _} =
        Inventory.create_purchase(%{
          "ingredient_code" => ingredient.code,
          "location_code" => location.code,
          "quantity" => 1000,
          "total_cost_pesos" => "50.00",
          "paid_from_account_id" => to_string(cash_account.id),
          "purchase_date" => Date.utc_today()
        })

      # Create duplicate order_in_prep (adds extra 2000 credit to 1200)
      {:ok, _} =
        Accounting.create_journal_entry(%{
          "date" => Date.utc_today(),
          "description" => "Order in prep",
          "entry_type" => "order_in_prep",
          "reference" => "Order #600",
          "journal_lines" => [
            %{"account_id" => wip_account.id, "debit_cents" => 2000},
            %{"account_id" => ingredients_account.id, "credit_cents" => 2000}
          ]
        })

      {:ok, _} =
        Accounting.create_journal_entry(%{
          "date" => Date.utc_today(),
          "description" => "Order in prep (duplicate)",
          "entry_type" => "order_in_prep",
          "reference" => "Order #600",
          "journal_lines" => [
            %{"account_id" => wip_account.id, "debit_cents" => 2000},
            %{"account_id" => ingredients_account.id, "credit_cents" => 2000}
          ]
        })

      # ALSO add a phantom debit (mismatch beyond what dedup fixes)
      {:ok, _} =
        Accounting.create_journal_entry(%{
          "date" => Date.utc_today(),
          "description" => "Phantom entry",
          "entry_type" => "other",
          "journal_lines" => [
            %{"account_id" => ingredients_account.id, "debit_cents" => 50000},
            %{"account_id" => cash_account.id, "credit_cents" => 50000}
          ]
        })

      assert {:error, _} = Verification.verify_inventory_cost_accounting()

      assert {:ok, results} = Verification.repair_inventory_cost_accounting()

      # Should have both steps
      step1 = Enum.find(results, fn r -> r[:step] == "1. Duplicate cleanup" end)
      assert step1 != nil
      assert step1.duplicates_removed >= 1

      step2 = Enum.find(results, fn r -> r[:step] == "2. Shrinkage adjustment" end)
      assert step2 != nil
      assert step2.action =~ "Created adjusting entry"

      # Should now be clean
      assert {:ok, _} = Verification.verify_inventory_cost_accounting()
    end
  end

  # ── repair_duplicate_cogs_entries ──────────────────────────────────────

  describe "repair_duplicate_cogs_entries/0" do
    test "deletes duplicate entries keeping the first one", %{
      wip_account: wip_account,
      ingredients_account: ingredients_account
    } do
      # Create two duplicate order_in_prep entries
      {:ok, first} =
        Accounting.create_journal_entry(%{
          "date" => Date.utc_today(),
          "description" => "Order in prep",
          "entry_type" => "order_in_prep",
          "reference" => "Order #300",
          "journal_lines" => [
            %{"account_id" => wip_account.id, "debit_cents" => 5000},
            %{"account_id" => ingredients_account.id, "credit_cents" => 5000}
          ]
        })

      {:ok, duplicate} =
        Accounting.create_journal_entry(%{
          "date" => Date.utc_today(),
          "description" => "Order in prep (dupe)",
          "entry_type" => "order_in_prep",
          "reference" => "Order #300",
          "journal_lines" => [
            %{"account_id" => wip_account.id, "debit_cents" => 5000},
            %{"account_id" => ingredients_account.id, "credit_cents" => 5000}
          ]
        })

      # Verify duplicates detected
      assert {:error, _} = Verification.verify_duplicate_cogs_entries()

      # Repair
      assert {:ok, results} = Verification.repair_duplicate_cogs_entries()
      assert length(results) > 0
      assert Enum.any?(results, fn r -> r.action =~ "Deleted duplicate" end)

      # Verify first entry still exists, duplicate is gone
      assert Repo.get(Accounting.JournalEntry, first.id) != nil
      assert Repo.get(Accounting.JournalEntry, duplicate.id) == nil

      # Verify check now passes
      assert {:ok, _} = Verification.verify_duplicate_cogs_entries()
    end

    test "returns empty list when no duplicates", %{
      wip_account: wip_account,
      ingredients_account: ingredients_account
    } do
      {:ok, _} =
        Accounting.create_journal_entry(%{
          "date" => Date.utc_today(),
          "description" => "Single entry",
          "entry_type" => "order_in_prep",
          "reference" => "Order #400",
          "journal_lines" => [
            %{"account_id" => wip_account.id, "debit_cents" => 5000},
            %{"account_id" => ingredients_account.id, "credit_cents" => 5000}
          ]
        })

      assert {:ok, []} = Verification.repair_duplicate_cogs_entries()
    end
  end

  # ── repair_withdrawal_accounts ─────────────────────────────────────────

  describe "repair_withdrawal_accounts/0" do
    test "creates correction entry for incorrect withdrawals", %{
      owners_equity_account: owners_equity_account,
      cash_account: cash_account
    } do
      # Create an incorrect withdrawal debiting Owner's Equity
      {:ok, _} =
        Accounting.create_journal_entry(%{
          "date" => Date.utc_today(),
          "description" => "Incorrect withdrawal",
          "entry_type" => "withdrawal",
          "reference" => "Withdrawal #10",
          "journal_lines" => [
            %{"account_id" => owners_equity_account.id, "debit_cents" => 10000},
            %{"account_id" => cash_account.id, "credit_cents" => 10000}
          ]
        })

      # Verify it's broken
      assert {:error, _} = Verification.verify_withdrawal_accounts()

      # Repair
      assert {:ok, [result]} = Verification.repair_withdrawal_accounts()
      assert result.action =~ "Created correction entry"
    end

    test "returns empty list when all withdrawals are correct", %{
      owners_drawings_account: owners_drawings_account,
      cash_account: cash_account
    } do
      {:ok, _} =
        Accounting.create_journal_entry(%{
          "date" => Date.utc_today(),
          "description" => "Correct withdrawal",
          "entry_type" => "withdrawal",
          "reference" => "Withdrawal #20",
          "journal_lines" => [
            %{"account_id" => owners_drawings_account.id, "debit_cents" => 5000},
            %{"account_id" => cash_account.id, "credit_cents" => 5000}
          ]
        })

      assert {:ok, []} = Verification.repair_withdrawal_accounts()
    end
  end

  # ── repair_gift_order_accounting ───────────────────────────────────────

  describe "repair_gift_order_accounting/0" do
    test "creates correction entry for gift order with sale-style accounting", %{
      wip_account: wip_account,
      cogs_account: cogs_account,
      location: location
    } do
      product = create_product()
      order = create_gift_order(product, location, "delivered")

      # Create a sale-style delivery entry (no 6070 line)
      {:ok, _} =
        Accounting.create_journal_entry(%{
          "date" => Date.utc_today(),
          "description" => "Order delivered (sale style)",
          "entry_type" => "order_delivered",
          "reference" => "Order ##{order.id}",
          "journal_lines" => [
            %{"account_id" => cogs_account.id, "debit_cents" => 3000},
            %{"account_id" => wip_account.id, "credit_cents" => 3000}
          ]
        })

      # Verify it's broken
      assert {:error, _} = Verification.verify_gift_order_accounting()

      # Repair
      assert {:ok, results} = Verification.repair_gift_order_accounting()
      assert length(results) > 0
      assert Enum.any?(results, fn r -> r.action =~ "correction entry" end)

      # Verify it's now fixed (correction entry has 6070 line)
      assert {:ok, %{checked: 1, issues: 0}} = Verification.verify_gift_order_accounting()
    end

    test "returns empty list when no gift orders need fixing" do
      assert {:ok, []} = Verification.repair_gift_order_accounting()
    end
  end

  # ── verify_duplicate_movements ────────────────────────────────────────

  describe "verify_duplicate_movements/0" do
    test "returns ok when no duplicate movements exist", %{
      cash_account: cash_account,
      ingredient: ingredient,
      location: location
    } do
      {:ok, _} =
        Inventory.create_purchase(%{
          "ingredient_code" => ingredient.code,
          "location_code" => location.code,
          "quantity" => 500,
          "total_cost_pesos" => "25.00",
          "paid_from_account_id" => to_string(cash_account.id),
          "purchase_date" => Date.utc_today()
        })

      assert {:ok, %{duplicate_groups: 0}} = Verification.verify_duplicate_movements()
    end

    test "returns error when duplicate movements exist", %{
      ingredient: ingredient,
      location: location
    } do
      # Insert two identical movements directly
      attrs = %{
        movement_type: "usage",
        ingredient_id: ingredient.id,
        from_location_id: location.id,
        quantity: 100,
        unit_cost_cents: 50,
        total_cost_cents: 5000,
        source_type: "order",
        source_id: 999,
        movement_date: Date.utc_today()
      }

      {:ok, _} = %InventoryMovement{} |> InventoryMovement.changeset(attrs) |> Repo.insert()
      {:ok, _} = %InventoryMovement{} |> InventoryMovement.changeset(attrs) |> Repo.insert()

      assert {:error, issues} = Verification.verify_duplicate_movements()
      assert length(issues) > 0
      assert Enum.any?(issues, fn issue -> String.contains?(issue, "Duplicate usage") end)
    end
  end

  # ── repair_duplicate_movements ──────────────────────────────────────

  describe "repair_duplicate_movements/0" do
    test "deletes duplicate movements keeping the first", %{
      ingredient: ingredient,
      location: location
    } do
      attrs = %{
        movement_type: "usage",
        ingredient_id: ingredient.id,
        from_location_id: location.id,
        quantity: 100,
        unit_cost_cents: 50,
        total_cost_cents: 5000,
        source_type: "order",
        source_id: 888,
        movement_date: Date.utc_today()
      }

      {:ok, first} = %InventoryMovement{} |> InventoryMovement.changeset(attrs) |> Repo.insert()
      {:ok, dupe} = %InventoryMovement{} |> InventoryMovement.changeset(attrs) |> Repo.insert()

      # Verify duplicates detected
      assert {:error, _} = Verification.verify_duplicate_movements()

      # Repair
      assert {:ok, results} = Verification.repair_duplicate_movements()
      assert length(results) > 0
      assert Enum.any?(results, fn r -> r.action =~ "Deleted duplicate" end)

      # First kept, dupe gone
      assert Repo.get(InventoryMovement, first.id) != nil
      assert Repo.get(InventoryMovement, dupe.id) == nil

      # Verify check now passes
      assert {:ok, %{duplicate_groups: 0}} = Verification.verify_duplicate_movements()
    end

    test "returns empty list when no duplicates" do
      assert {:ok, []} = Verification.repair_duplicate_movements()
    end
  end

  # ── run_repair dispatcher ──────────────────────────────────────────────

  describe "run_repair/1" do
    test "dispatches to correct repair function" do
      # All repair types should work (no errors at least)
      assert {:ok, _} = Verification.run_repair("inventory_quantities")
      assert {:ok, _} = Verification.run_repair("duplicate_cogs_entries")
      assert {:ok, _} = Verification.run_repair("duplicate_movements")
      assert {:ok, _} = Verification.run_repair("movement_costs")
    end

    test "returns error for unknown repair type" do
      assert {:error, msg} = Verification.run_repair("nonexistent")
      assert msg =~ "Unknown repair type"
    end
  end

  # ── repairable? ────────────────────────────────────────────────────────

  describe "repairable?/1" do
    test "returns true for repairable checks" do
      assert Verification.repairable?(:inventory_quantities)
      assert Verification.repairable?(:inventory_cost_accounting)
      assert Verification.repairable?(:duplicate_cogs_entries)
      assert Verification.repairable?(:duplicate_movements)
      assert Verification.repairable?(:withdrawal_accounts)
      assert Verification.repairable?(:gift_order_accounting)
      assert Verification.repairable?(:movement_costs)
    end

    test "returns false for non-repairable checks" do
      refute Verification.repairable?(:wip_balance)
      refute Verification.repairable?(:journal_entries_balanced)
      refute Verification.repairable?(:order_wip_consistency)
    end
  end

  # ── run_all_checks ─────────────────────────────────────────────────────

  describe "run_all_checks/0" do
    test "runs all 10 verification checks and returns results", %{
      cash_account: cash_account,
      ingredient: ingredient,
      location: location
    } do
      {:ok, _} =
        Inventory.create_purchase(%{
          "ingredient_code" => ingredient.code,
          "location_code" => location.code,
          "quantity" => 1000,
          "total_cost_pesos" => "50.00",
          "paid_from_account_id" => to_string(cash_account.id),
          "purchase_date" => Date.utc_today()
        })

      results = Verification.run_all_checks()

      # Verify all 10 check keys are present
      assert Map.has_key?(results, :inventory_quantities)
      assert Map.has_key?(results, :inventory_cost_accounting)
      assert Map.has_key?(results, :movement_costs)
      assert Map.has_key?(results, :duplicate_movements)
      assert Map.has_key?(results, :wip_balance)
      assert Map.has_key?(results, :order_wip_consistency)
      assert Map.has_key?(results, :journal_entries_balanced)
      assert Map.has_key?(results, :duplicate_cogs_entries)
      assert Map.has_key?(results, :withdrawal_accounts)
      assert Map.has_key?(results, :gift_order_accounting)

      assert map_size(results) == 10

      # All should pass in a clean test environment
      Enum.each(results, fn {check_name, result} ->
        assert match?({:ok, _}, result), "Check #{check_name} failed: #{inspect(result)}"
      end)
    end
  end

  # ── Private helpers ────────────────────────────────────────────────────

  defp create_product do
    alias MrMunchMeAccountingApp.Orders.Product

    {:ok, product} =
      %Product{}
      |> Product.changeset(%{
        sku: "GIFT-#{System.unique_integer([:positive])}",
        name: "Gift Product",
        price_cents: 10000,
        active: true
      })
      |> Repo.insert()

    product
  end

  defp create_gift_order(product, location, status) do
    {:ok, order} =
      %Order{}
      |> Order.changeset(%{
        customer_name: "Gift Recipient",
        customer_phone: "5559999999",
        product_id: product.id,
        prep_location_id: location.id,
        delivery_date: Date.utc_today(),
        delivery_type: "pickup",
        status: status,
        is_gift: true
      })
      |> Repo.insert()

    order
  end
end
