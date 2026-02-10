defmodule Ledgr.Core.Accounting.JournalEntryTest do
  use Ledgr.DataCase, async: true

  alias Ledgr.Core.Accounting

  setup do
    # Create minimal accounts needed for tests
    {:ok, cash} =
      Accounting.create_account(%{
        code: "1000",
        name: "Cash",
        type: "asset",
        normal_balance: "debit",
        is_cash: true
      })

    {:ok, sales} =
      Accounting.create_account(%{
        code: "4000",
        name: "Sales Revenue",
        type: "revenue",
        normal_balance: "credit",
        is_cash: false
      })

    {:ok, cash: cash, sales: sales}
  end

  test "accepts a balanced entry", %{cash: cash, sales: sales} do
    attrs = %{
      "date" => "2025-01-01",
      "description" => "Test sale",
      "entry_type" => "sale",
      "journal_lines" => [
        %{"account_id" => cash.id, "debit_cents" => 100_00},
        %{"account_id" => sales.id, "credit_cents" => 100_00}
      ]
    }

    assert {:ok, entry} = Accounting.create_journal_entry(attrs)
    assert entry.date == ~D[2025-01-01]
    assert length(entry.journal_lines) == 2
  end

  test "rejects an unbalanced entry", %{cash: cash, sales: sales} do
    attrs = %{
      "date" => "2025-01-02",
      "description" => "Broken sale",
      "entry_type" => "sale",
      "journal_lines" => [
        %{"account_id" => cash.id, "debit_cents" => 100_00},
        %{"account_id" => sales.id, "credit_cents" => 90_00}
      ]
    }

    assert {:error, changeset} = Accounting.create_journal_entry(attrs)
    assert "Debits and credits must be equal and non-zero" in errors_on(changeset).base
  end

  test "rejects zero-total entry", %{cash: cash, sales: sales} do
    attrs = %{
      "date" => "2025-01-03",
      "description" => "Zero entry",
      "entry_type" => "sale",
      "journal_lines" => [
        %{"account_id" => cash.id, "debit_cents" => 0},
        %{"account_id" => sales.id, "credit_cents" => 0}
      ]
    }

    assert {:error, changeset} = Accounting.create_journal_entry(attrs)

    # When both debit and credit are 0, the line-level validation adds errors
    # errors_on(changeset).journal_lines returns a list of error maps (one per line)
    line_errors = errors_on(changeset).journal_lines
    assert is_list(line_errors)
    assert length(line_errors) == 2

    # Each line should have a base error about needing a debit or credit
    Enum.each(line_errors, fn line_error_map ->
      assert "line must have a debit or a credit" in line_error_map.base
    end)
  end
end
