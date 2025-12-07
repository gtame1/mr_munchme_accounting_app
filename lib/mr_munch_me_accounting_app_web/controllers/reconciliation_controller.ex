defmodule MrMunchMeAccountingAppWeb.ReconciliationController do
  use MrMunchMeAccountingAppWeb, :controller
  require Logger

  alias MrMunchMeAccountingApp.Reconciliation
  alias MrMunchMeAccountingApp.Accounting

  # ---------- Accounting Reconciliation ----------

  def accounting_index(conn, params) do
    as_of =
      case Map.get(params, "as_of") do
        nil -> Date.utc_today()
        "" -> Date.utc_today()
        date_str -> Date.from_iso8601!(date_str)
      end

    accounts = Reconciliation.list_accounts_for_reconciliation(as_of)

    render(conn, :accounting_index,
      accounts: accounts,
      as_of: as_of
    )
  end

  def accounting_adjust(conn, params) do
    account_id = params["account_id"]
    actual_balance_str = params["actual_balance"]
    date_str = params["adjustment_date"]
    description = params["description"]

    if is_nil(account_id) or is_nil(actual_balance_str) or is_nil(date_str) do
      conn
      |> put_flash(:error, "Missing required fields")
      |> redirect(to: ~p"/reconciliation/accounting")
    else
      _account = Accounting.get_account!(account_id)

      actual_balance =
        case Float.parse(actual_balance_str) do
          {float_val, _} -> float_val
          :error ->
            # Try parsing as integer and converting to float
            case Integer.parse(actual_balance_str) do
              {int_val, _} -> int_val * 1.0
              :error -> raise ArgumentError, "Invalid balance value: #{actual_balance_str}"
            end
        end

      adjustment_date = Date.from_iso8601!(date_str)

    case Reconciliation.create_account_reconciliation(
           account_id,
           actual_balance,
           adjustment_date,
           description
         ) do
      {:ok, _journal_entry} ->
        conn
        |> put_flash(:info, "Reconciliation adjustment created successfully")
        |> redirect(to: ~p"/reconciliation/accounting")

      {:error, reason} when is_binary(reason) ->
        conn
        |> put_flash(:error, reason)
        |> redirect(to: ~p"/reconciliation/accounting")

      {:error, changeset} ->
        error_msg =
          case changeset.errors do
            [] -> "Failed to create adjustment"
            errors -> "Failed to create adjustment: #{inspect(errors)}"
          end

        conn
        |> put_flash(:error, error_msg)
        |> redirect(to: ~p"/reconciliation/accounting")
      end
    end
  end

  # ---------- Inventory Reconciliation ----------

  def inventory_index(conn, _params) do
    inventory_items = Reconciliation.list_inventory_for_reconciliation()

    render(conn, :inventory_index,
      inventory_items: inventory_items
    )
  end

  def inventory_adjust(conn, params) do
    Logger.info("Inventory adjust called with params: #{inspect(params)}")

    ingredient_id = params["ingredient_id"]
    location_id = params["location_id"]
    actual_quantity_str = params["actual_quantity"]
    date_str = params["adjustment_date"]
    description = params["description"]

    Logger.info("Parsed values - ingredient_id: #{inspect(ingredient_id)}, location_id: #{inspect(location_id)}, actual_quantity_str: #{inspect(actual_quantity_str)}, date_str: #{inspect(date_str)}")

    if is_nil(ingredient_id) or is_nil(location_id) or is_nil(actual_quantity_str) or is_nil(date_str) do
      Logger.warn("Missing required fields in inventory adjust")
      conn
      |> put_flash(:error, "Missing required fields")
      |> redirect(to: ~p"/reconciliation/inventory")
    else
      try do
        actual_quantity = String.to_integer(actual_quantity_str)
        adjustment_date = Date.from_iso8601!(date_str)

        Logger.info("Calling create_inventory_reconciliation with ingredient_id: #{ingredient_id}, location_id: #{location_id}, actual_quantity: #{actual_quantity}, adjustment_date: #{adjustment_date}")

        case Reconciliation.create_inventory_reconciliation(
               ingredient_id,
               location_id,
               actual_quantity,
               adjustment_date,
               description
             ) do
          {:ok, result} ->
            Logger.info("Inventory reconciliation successful: #{inspect(result)}")
            conn
            |> put_flash(:info, "Inventory reconciliation adjustment created successfully")
            |> redirect(to: ~p"/reconciliation/inventory")

          {:error, reason} when is_binary(reason) ->
            Logger.warn("Inventory reconciliation error (string): #{reason}")
            conn
            |> put_flash(:error, reason)
            |> redirect(to: ~p"/reconciliation/inventory")

          {:error, changeset} ->
            Logger.error("Inventory reconciliation error (changeset): #{inspect(changeset.errors)}")
            error_msg =
              case changeset.errors do
                [] -> "Failed to create adjustment"
                errors -> "Failed to create adjustment: #{inspect(errors)}"
              end

            conn
            |> put_flash(:error, error_msg)
            |> redirect(to: ~p"/reconciliation/inventory")

          other ->
            Logger.error("Unexpected result from create_inventory_reconciliation: #{inspect(other)}")
            conn
            |> put_flash(:error, "Unexpected error: #{inspect(other)}")
            |> redirect(to: ~p"/reconciliation/inventory")
        end
      rescue
        e ->
          Logger.error("Exception in inventory_adjust: #{inspect(e)} - #{Exception.format(:error, e, __STACKTRACE__)}")
          conn
          |> put_flash(:error, "Error: #{Exception.message(e)}")
          |> redirect(to: ~p"/reconciliation/inventory")
      end
    end
  end
end


defmodule MrMunchMeAccountingAppWeb.ReconciliationHTML do
  use MrMunchMeAccountingAppWeb, :html

  import MrMunchMeAccountingAppWeb.CoreComponents

  embed_templates "reconciliation_html/*"
end
