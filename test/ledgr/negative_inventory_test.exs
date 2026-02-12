defmodule Ledgr.Domains.MrMunchMe.NegativeInventoryTest do
  use Ledgr.DataCase, async: true

  alias Ledgr.Domains.MrMunchMe.Inventory
  alias Ledgr.Domains.MrMunchMe.Inventory.{InventoryItem, Ingredient, Location}
  alias Ledgr.Repo

  import Ledgr.Core.AccountingFixtures

  setup do
    accounts = standard_accounts_fixture()

    # Ensure accounts needed by inventory accounting exist
    for {code, name, type, normal_balance} <- [
          {"1300", "Kitchen Equipment", "asset", "debit"},
          {"1310", "Accumulated Depreciation", "asset", "credit"},
          {"1400", "IVA Receivable", "asset", "debit"},
          {"2100", "Sales Tax Payable", "liability", "credit"},
          {"6045", "Depreciation Expense", "expense", "debit"},
          {"6060", "Inventory Waste", "expense", "debit"}
        ] do
      case Ledgr.Core.Accounting.get_account_by_code(code) do
        nil ->
          Ledgr.Core.Accounting.create_account(%{
            code: code,
            name: name,
            type: type,
            normal_balance: normal_balance,
            is_cash: false
          })

        _ ->
          :ok
      end
    end

    # Create unique codes per test to avoid async conflicts
    unique = System.unique_integer([:positive])
    ingredient_code = "FLOUR_#{unique}"
    location_code = "MAIN_#{unique}"

    # Create a location
    {:ok, location} =
      %Location{}
      |> Location.changeset(%{name: "Main Kitchen", code: location_code})
      |> Repo.insert()

    # Create an ingredient
    {:ok, ingredient} =
      %Ingredient{}
      |> Ingredient.changeset(%{
        code: ingredient_code,
        name: "Flour",
        unit: "kg",
        cost_per_unit_cents: 500,
        inventory_type: "ingredients"
      })
      |> Repo.insert()

    cash = accounts["1000"]

    # Purchase initial stock of 10 units via the real API
    {:ok, _} =
      Inventory.record_purchase(
        ingredient_code,
        location_code,
        10,
        cash.id,
        500,
        Date.utc_today()
      )

    stock = Inventory.get_or_create_stock!(ingredient.id, location.id)

    %{
      accounts: accounts,
      location: location,
      ingredient: ingredient,
      ingredient_code: ingredient_code,
      location_code: location_code,
      stock: stock,
      cash: cash
    }
  end

  describe "negative_stock flag on purchase (record_purchase)" do
    test "receiving stock keeps negative_stock false when already positive", %{
      ingredient_code: ing_code,
      location_code: loc_code,
      ingredient: ingredient,
      location: location,
      cash: cash
    } do
      {:ok, _} =
        Inventory.record_purchase(
          ing_code,
          loc_code,
          5,
          cash.id,
          600,
          Date.utc_today()
        )

      stock = Inventory.get_or_create_stock!(ingredient.id, location.id)
      refute stock.negative_stock
      assert stock.quantity_on_hand == 15
    end

    test "receiving stock clears negative_stock flag when recovering from negative", %{
      ingredient: ingredient,
      location: location,
      ingredient_code: ing_code,
      location_code: loc_code,
      cash: cash
    } do
      # First, consume more than available to go negative
      {:ok, _} = Inventory.record_usage(ing_code, loc_code, 15, Date.utc_today(), "manual")

      stock = Inventory.get_or_create_stock!(ingredient.id, location.id)
      assert stock.negative_stock == true
      assert stock.quantity_on_hand == -5

      # Now receive stock to recover
      {:ok, _} =
        Inventory.record_purchase(
          ing_code,
          loc_code,
          10,
          cash.id,
          500,
          Date.utc_today()
        )

      stock = Inventory.get_or_create_stock!(ingredient.id, location.id)
      refute stock.negative_stock
      assert stock.quantity_on_hand == 5
    end
  end

  describe "negative_stock flag on consumption (record_usage)" do
    test "consuming less than available keeps flag false", %{
      ingredient_code: ing_code,
      location_code: loc_code,
      ingredient: ingredient,
      location: location
    } do
      {:ok, _} = Inventory.record_usage(ing_code, loc_code, 3, Date.utc_today(), "manual")

      stock = Inventory.get_or_create_stock!(ingredient.id, location.id)
      refute stock.negative_stock
      assert stock.quantity_on_hand == 7
    end

    test "consuming more than available sets negative_stock flag", %{
      ingredient_code: ing_code,
      location_code: loc_code,
      ingredient: ingredient,
      location: location
    } do
      {:ok, _} = Inventory.record_usage(ing_code, loc_code, 15, Date.utc_today(), "manual")

      stock = Inventory.get_or_create_stock!(ingredient.id, location.id)
      assert stock.negative_stock == true
      assert stock.quantity_on_hand == -5
    end

    test "consuming exactly available quantity keeps flag false", %{
      ingredient_code: ing_code,
      location_code: loc_code,
      ingredient: ingredient,
      location: location
    } do
      {:ok, _} = Inventory.record_usage(ing_code, loc_code, 10, Date.utc_today(), "manual")

      stock = Inventory.get_or_create_stock!(ingredient.id, location.id)
      refute stock.negative_stock
      assert stock.quantity_on_hand == 0
    end
  end

  describe "list_negative_stock_items/0" do
    test "returns empty list when no items are negative" do
      assert Inventory.list_negative_stock_items() == []
    end

    test "returns items with negative_stock flag set", %{
      ingredient_code: ing_code,
      location_code: loc_code
    } do
      # Consume more than available to trigger negative flag
      {:ok, _} = Inventory.record_usage(ing_code, loc_code, 12, Date.utc_today(), "manual")

      items = Inventory.list_negative_stock_items()
      assert length(items) == 1
      assert hd(items).quantity_on_hand == -2
      assert hd(items).negative_stock == true
    end

    test "does not return items that have recovered from negative", %{
      ingredient_code: ing_code,
      location_code: loc_code,
      cash: cash
    } do
      # Go negative
      {:ok, _} = Inventory.record_usage(ing_code, loc_code, 15, Date.utc_today(), "manual")
      assert length(Inventory.list_negative_stock_items()) == 1

      # Recover by restocking
      {:ok, _} =
        Inventory.record_purchase(
          ing_code,
          loc_code,
          20,
          cash.id,
          500,
          Date.utc_today()
        )

      assert Inventory.list_negative_stock_items() == []
    end
  end
end
