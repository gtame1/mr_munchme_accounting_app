defmodule MrMunchMeAccountingApp.Accounting do
  @moduledoc """
  Accounting context: chart of accounts and double-entry journal.
  """
  import Ecto.Query, warn: false
  import Ecto.Changeset   # ⬅️ add this

  alias MrMunchMeAccountingApp.Repo
  alias MrMunchMeAccountingApp.Orders.{Order, OrderPayment, Product}
  alias MrMunchMeAccountingApp.Inventory
  alias MrMunchMeAccountingApp.Accounting.{Account, JournalEntry, JournalLine, MoneyTransfer}
  alias MrMunchMeAccountingApp.Expenses.Expense
  alias MrMunchMeAccountingApp.Partners.CapitalContribution



  @ar_code "1100"
  @cash_code "1000"   # or "1010" if you prefer Bank as default
  @ingredients_inventory_code "1200"   # Ingredients Inventory
  @packing_inventory_code "1210"   # Packing Materials Inventory
  @wip_inventory_code "1220"   # Ingredients Inventory (WIP)
  @kitchen_inventory_code "1300"   # Kitchen Equipment Inventory
  @customer_deposits_code "2200"   # Customer Deposits Liability
  @sales_code "4000"
  @owners_equity_code "3000"
  @ingredients_cogs_code "5000"
  @packaging_cogs_code "5010"
  @inventory_waste_code "6060"
  @other_expenses_code "6099"

  @shipping_product_sku "ENVIO"


  # ---------- Accounting for movements ----------

  def handle_order_status_change(%Order{} = order, new_status) do
    case new_status do
      "in_prep" ->
        total_cost_cents = Inventory.consume_for_order(order)
        record_order_in_prep(order, total_cost_cents)
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

    Dr WIP Inventory (1210)
    Cr Ingredients Inventory (1200)
  """
  def record_order_in_prep(%Order{} = order, total_cost_cents) do
    wip        = get_account_by_code!(@wip_inventory_code)
    ingredients = get_account_by_code!(@ingredients_inventory_code)

    entry_attrs = %{
      date: order.delivery_date || Date.utc_today(),
      entry_type: "order_in_prep",
      reference: "Order ##{order.id}",
      description: "Move ingredients to WIP for order ##{order.id}"
    }

    lines = [
      %{
        account_id: wip.id,
        debit_cents: total_cost_cents,
        credit_cents: 0,
        description: "WIP for order ##{order.id}"
      },
      %{
        account_id: ingredients.id,
        debit_cents: 0,
        credit_cents: total_cost_cents,
        description: "Ingredients used for order ##{order.id}"
      }
    ]

    create_journal_entry_with_lines(entry_attrs, lines)
  end


  def record_order_delivered(%Order{} = order) do
    order = Repo.preload(order, :product)

    base_revenue  = order.product.price_cents || 0

    # If customer_paid_shipping == true, add shipping revenue
    shipping_cents =
      if order.customer_paid_shipping do
        shipping_fee_cents()
      else
        0
      end

    revenue_cents = base_revenue + shipping_cents

    # Get the production cost from the "order_in_prep" journal entry (WIP debit)
    # This was recorded when the order moved to "in_prep"
    wip = get_account_by_code!(@wip_inventory_code)
    cost_cents = get_order_production_cost(order.id, wip.id) || 0

    ar    = get_account_by_code!(@ar_code)
    sales = get_account_by_code!(@sales_code)
    customer_deposits = get_account_by_code!(@customer_deposits_code)

    # For now, ALL COGS → Ingredients Used (5000).
    # Later we can split into ingredients vs packaging if we have separate numbers.
    ingredients_cogs = get_account_by_code!(@ingredients_cogs_code)
    # packaging_cogs   = get_account_by_code!(@packaging_cogs_code) # (for future use)

    date = order.delivery_date || Date.utc_today()

    entry_attrs = %{
      date: date,
      entry_type: "order_delivered",
      reference: "Order ##{order.id}",
      description: "Delivered order ##{order.id}"
    }

    # Calculate total deposits paid before delivery
    # Deposits are payments where is_deposit == true
    # Use customer_amount_cents if set, otherwise use amount_cents
    deposit_total_cents =
      from(p in OrderPayment,
        where: p.order_id == ^order.id and p.is_deposit == true,
        select: sum(fragment("COALESCE(?, ?)", p.customer_amount_cents, p.amount_cents))
      )
      |> Repo.one()
      |> case do
        nil -> 0
        total -> total
      end

    # 1) Revenue: DR AR, CR Sales
    revenue_lines =
      if revenue_cents > 0 do
        [
          %{
            account_id: ar.id,
            debit_cents: revenue_cents,
            credit_cents: 0,
            description: "Recognize AR for order ##{order.id}"
          },
          %{
            account_id: sales.id,
            debit_cents: 0,
            credit_cents: revenue_cents,
            description:
              if shipping_cents > 0 do
                "Sales (product + shipping) for order ##{order.id}"
              else
                "Sales revenue for order ##{order.id}"
              end
          }
        ]
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

    # 3) COGS: DR COGS, CR WIP
    # For now, post all cost to Ingredients COGS (5000).
    cogs_lines =
      if cost_cents > 0 do
        [
          %{
            account_id: ingredients_cogs.id,
            debit_cents: cost_cents,
            credit_cents: 0,
            description: "COGS for order ##{order.id}"
          },
          %{
            account_id: wip.id,
            debit_cents: 0,
            credit_cents: cost_cents,
            description: "Relieve WIP for order ##{order.id}"
          }
        ]
      else
        []
      end

    lines = revenue_lines ++ deposit_transfer_lines ++ cogs_lines

    create_journal_entry_with_lines(entry_attrs, lines)
  end

  # For now, we do not create any accounting entry on cancellation.
  # (We only allow cancelling orders that have not yet been delivered in the UI.)
  # Later, if you want to reverse WIP for in_prep orders, we can handle that separately.
  def record_order_canceled(%Order{} = _order), do: :ok

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

    create_journal_entry_with_lines(entry_attrs, lines)
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

        update_journal_entry_with_lines(journal_entry, entry_attrs, lines)
      end
    else
      # If journal entry doesn't exist, create it
      record_order_payment(payment)
    end
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
        get_account_by_code!(@customer_deposits_code)
      else
        get_account_by_code!(@ar_code)
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
        get_account_by_code!(@customer_deposits_code)
      else
        get_account_by_code!(@ar_code)
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

  @doc """
  Record an inventory purchase:
    - Debit Ingredients Inventory (1200)
    - Credit Cash (1000)

  `total_cost_cents` is the *total* MXN cost in cents.

  `opts` can include:
    - :reference (e.g. "INV-123" or "Purchase FLOUR")
    - :description override
  """
  def record_inventory_purchase(total_cost_cents, opts \\ []) do
    # 1) Decide which inventory account we’re debiting
    {inv_account, inventory_type} =
      cond do
        Keyword.get(opts, :packing, false) -> {get_account_by_code!(@packing_inventory_code), "Packing"}
        Keyword.get(opts, :kitchen, false) -> {get_account_by_code!(@kitchen_inventory_code), "Kitchen"}
        true -> {get_account_by_code!(@ingredients_inventory_code), "Ingredients"}
      end

    # 2) Decide which account we’re CREDITING (paid from)
    paid_from_account =
      cond do
        # already have an account struct
        acc = Keyword.get(opts, :paid_from_account) -> acc
        id = Keyword.get(opts, :paid_from_account_id) ->
          id =
            case id do
              i when is_binary(i) ->
                case Integer.parse(i) do
                  {parsed, _} -> parsed
                  :error -> raise "Invalid paid_from_account_id: #{inspect(id)}"
                end

              i when is_integer(i) ->
                i
            end

          Repo.get!(MrMunchMeAccountingApp.Accounting.Account, id)

        # passed an account code like "1010"
        code = Keyword.get(opts, :paid_from_account_code) -> get_account_by_code!(code)

        # fallback → cash
        true -> get_account_by_code!(@cash_code)
      end

    date = Keyword.get(opts, :purchase_date, Date.utc_today())
    reference = Keyword.get(opts, :reference)

    description =
      Keyword.get(opts, :description,
        "#{inventory_type} inventory purchase (paid from #{paid_from_account.code})"
      )

    entry_attrs = %{
      date: date,
      entry_type: "inventory_purchase",
      reference: reference,
      description: description
    }

    lines = [
      %{
        account_id: inv_account.id,
        debit_cents: total_cost_cents,
        credit_cents: 0,
        description: "Increase #{inventory_type} inventory"
      },
      %{
        account_id: paid_from_account.id,
        debit_cents: 0,
        credit_cents: total_cost_cents,
        description: "Paid from #{paid_from_account.code} – #{paid_from_account.name}"
      }
    ]

    create_journal_entry_with_lines(entry_attrs, lines)
  end

  @doc """
  Record multiple inventory purchases in a single journal entry.
  Creates debit lines for each inventory type (ingredients, packing, kitchen)
  and a single credit line for the total payment.

  Args:
    - total_cost_by_type: %{ingredients: cents, packing: cents, kitchen: cents}
    - opts: keyword list with :purchase_date, :paid_from_account_id, :reference, :description
  """
  def record_multi_inventory_purchase(total_cost_by_type, opts \\ []) do
    # Get the accounts for each inventory type
    ingredients_account = get_account_by_code!(@ingredients_inventory_code)
    packing_account = get_account_by_code!(@packing_inventory_code)
    kitchen_account = get_account_by_code!(@kitchen_inventory_code)

    # Decide which account we're CREDITING (paid from)
    paid_from_account =
      cond do
        acc = Keyword.get(opts, :paid_from_account) -> acc
        id = Keyword.get(opts, :paid_from_account_id) ->
          id =
            case id do
              i when is_binary(i) ->
                case Integer.parse(i) do
                  {parsed, _} -> parsed
                  :error -> raise "Invalid paid_from_account_id: #{inspect(id)}"
                end

              i when is_integer(i) ->
                i
            end

          Repo.get!(Account, id)

        code = Keyword.get(opts, :paid_from_account_code) -> get_account_by_code!(code)
        true -> get_account_by_code!(@cash_code)
      end

    date = Keyword.get(opts, :purchase_date, Date.utc_today())
    reference = Keyword.get(opts, :reference)
    description = Keyword.get(opts, :description, "Multiple inventory purchases")

    # Build debit lines for each inventory type that has a cost
    lines = []

    lines =
      if total_cost_by_type.ingredients > 0 do
        [
          %{
            account_id: ingredients_account.id,
            debit_cents: total_cost_by_type.ingredients,
            credit_cents: 0,
            description: "Increase Ingredients inventory"
          }
          | lines
        ]
      else
        lines
      end

    lines =
      if total_cost_by_type.packing > 0 do
        [
          %{
            account_id: packing_account.id,
            debit_cents: total_cost_by_type.packing,
            credit_cents: 0,
            description: "Increase Packing inventory"
          }
          | lines
        ]
      else
        lines
      end

    lines =
      if total_cost_by_type.kitchen > 0 do
        [
          %{
            account_id: kitchen_account.id,
            debit_cents: total_cost_by_type.kitchen,
            credit_cents: 0,
            description: "Increase Kitchen inventory"
          }
          | lines
        ]
      else
        lines
      end

    # Calculate total cost for credit line
    total_cost_cents =
      total_cost_by_type.ingredients + total_cost_by_type.packing + total_cost_by_type.kitchen

    # Add single credit line
    lines = [
      %{
        account_id: paid_from_account.id,
        debit_cents: 0,
        credit_cents: total_cost_cents,
        description: "Paid from #{paid_from_account.code} – #{paid_from_account.name}"
      }
      | lines
    ]

    entry_attrs = %{
      date: date,
      entry_type: "inventory_purchase",
      reference: reference,
      description: description
    }

    create_journal_entry_with_lines(entry_attrs, Enum.reverse(lines))
  end

  @doc """
  Record a partner investment:

    - Debit Cash (1000)
    - Credit Owner's Equity (3000)

  Options:
    - :date (Date)
    - :partner_name (string)
  """
  def record_investment(amount_cents, opts) do
    cash_account_id = Keyword.fetch!(opts, :cash_account_id)
    date            = Keyword.get(opts, :date, Date.utc_today())
    partner_name    = Keyword.get(opts, :partner_name, "Partner")

    cash_account = Repo.get!(Account, cash_account_id)
    equity_account = get_account_by_code!(@owners_equity_code)

    entry_attrs = %{
      date: date,
      entry_type: "investment",
      reference: "Partner investment",
      description: "Investment from #{partner_name} into #{cash_account.name}"
    }

    lines = [
      %{
        account_id: cash_account.id,
        debit_cents: amount_cents,
        credit_cents: 0,
        description: "Cash received from #{partner_name}"
      },
      %{
        account_id: equity_account.id,
        debit_cents: 0,
        credit_cents: amount_cents,
        description: "Increase in owner's equity (#{partner_name})"
      }
    ]

    create_journal_entry_with_lines(entry_attrs, lines)
  end

  def record_withdrawal(amount_cents, opts) do
    cash_account_id = Keyword.fetch!(opts, :cash_account_id)
    date            = Keyword.get(opts, :date, Date.utc_today())
    partner_name    = Keyword.get(opts, :partner_name, "Partner")

    cash_account   = Repo.get!(Account, cash_account_id)
    equity_account = get_account_by_code!(@owners_equity_code)

    entry_attrs = %{
      date: date,
      entry_type: "withdrawal",
      reference: "Partner withdrawal",
      description: "Withdrawal by #{partner_name} from #{cash_account.name}"
    }

    lines = [
      %{
        account_id: equity_account.id,
        debit_cents: amount_cents,
        credit_cents: 0,
        description: "Reduce owner's equity (#{partner_name})"
      },
      %{
        account_id: cash_account.id,
        debit_cents: 0,
        credit_cents: amount_cents,
        description: "Cash paid out to #{partner_name}"
      }
    ]

    create_journal_entry_with_lines(entry_attrs, lines)
  end


  # ---------- Accounts ----------

  def list_accounts do
    Repo.all(from a in Account, order_by: [asc: a.code])
  end

  def get_account!(id), do: Repo.get!(Account, id)
  def get_account_by_code!(code), do: Repo.get_by!(Account, code: code)

  def create_account(attrs \\ %{}) do
    %Account{}
    |> Account.changeset(attrs)
    |> Repo.insert()
  end

  # For select inputs: [{"1000 - Cash", 1}, ...]
  def account_select_options do
    list_accounts()
    |> Enum.map(fn a -> {"#{a.code} - #{a.name}", a.id} end)
  end

  def cash_or_bank_account_options do
    Repo.all(
      from a in Account,
        where: a.type == "asset" and (a.is_cash == true or like(a.name, "%bank%")),
        order_by: a.code
    )
    |> Enum.map(fn a -> {"#{a.code} – #{a.name}", a.id} end)
  end

  def cash_or_payable_account_options do
    Repo.all(
      from a in Account,
        where: like(a.code, "10%") or like(a.code, "20%"),
        order_by: [asc: a.code]
    )
    |> Enum.map(fn a ->
      {"#{a.code} – #{a.name}", a.id}
    end)
  end

  def transfer_account_options do
    from(a in Account,
      where: a.type == "asset",
      order_by: a.code
    )
    |> Repo.all()
    |> Enum.map(fn a ->
      {"#{a.code} – #{a.name}", a.id}
    end)
  end

  # helper to build account select options
  def expense_account_options do
    from(a in Account, where: a.type == "expense", order_by: a.code)
    |> Repo.all()
    |> Enum.map(&{"#{&1.code} – #{&1.name}", &1.id})
  end

  def liability_account_options do
    from(a in Account, where: a.type == "liability", order_by: a.code)
    |> Repo.all()
    |> Enum.map(&{"#{&1.code} – #{&1.name}", &1.id})
  end

  # ---------- Journal entries ----------

  def list_journal_entries do
    Repo.all(
      from e in JournalEntry,
        order_by: [desc: e.date, desc: e.inserted_at]
    )
    |> Repo.preload(journal_lines: [:account])
    |> Enum.map(&put_totals/1)
  end

  def list_recent_journal_entries(limit \\ 5) do
    Repo.all(
      from e in JournalEntry,
        order_by: [desc: e.date, desc: e.inserted_at],
        limit: ^limit
    )
    |> Repo.preload(journal_lines: [:account])
    |> Enum.map(&put_totals/1)
  end

  def get_journal_entry!(id) do
    Repo.get!(JournalEntry, id)
    |> Repo.preload(journal_lines: [:account])
    |> put_totals()
  end

  def list_journal_lines_by_account(account_id, opts \\ []) do
    import Ecto.Query

    date_from = Keyword.get(opts, :date_from)
    date_to = Keyword.get(opts, :date_to)

    query =
      from jl in JournalLine,
        where: jl.account_id == ^account_id,
        join: je in assoc(jl, :journal_entry),
        join: a in assoc(jl, :account),
        preload: [journal_entry: je, account: a],
        order_by: [desc: je.date, desc: je.inserted_at, desc: jl.id]

    query =
      cond do
        date_from && date_to ->
          from [jl, je] in query,
            where: je.date >= ^date_from and je.date <= ^date_to

        date_from ->
          from [jl, je] in query,
            where: je.date >= ^date_from

        date_to ->
          from [jl, je] in query,
            where: je.date <= ^date_to

        true ->
          query
      end

    Repo.all(query)
  end

  def change_journal_entry(%JournalEntry{} = entry, attrs \\ %{}) do
    JournalEntry.changeset(entry, attrs)
  end

  def create_journal_entry(attrs) do
    %JournalEntry{}
    |> JournalEntry.changeset(attrs)
    |> Repo.insert()
  end

  def create_journal_entry_with_lines(entry_attrs, lines_attrs) do
    line_changesets =
      Enum.map(lines_attrs, fn attrs ->
        JournalLine.changeset(%JournalLine{}, attrs)
      end)

    %JournalEntry{}
    |> JournalEntry.changeset(entry_attrs)
    |> put_assoc(:journal_lines, line_changesets)
    |> Repo.insert()
  end

  def update_journal_entry_with_lines(%JournalEntry{} = entry, entry_attrs, lines_attrs) do
    line_changesets =
      Enum.map(lines_attrs, fn attrs ->
        JournalLine.changeset(%JournalLine{}, attrs)
      end)

    entry
    |> Repo.preload(:journal_lines)
    |> JournalEntry.changeset(entry_attrs)
    |> put_assoc(:journal_lines, line_changesets)
    |> Repo.update()
  end



  # -------- record_expense --------

  @doc """
  Given a persisted %Expense{}, creates an 'expense' journal entry:

    Debit: expense_account (amount_cents)
    Credit: paid_from_account (amount_cents)
  """
  def record_expense(%Expense{} = expense) do
    lines = [
      %{
        account_id: expense.expense_account_id,
        debit_cents: expense.amount_cents,
        credit_cents: 0,
        description: "Expense: #{expense.description}"
      },
      %{
        account_id: expense.paid_from_account_id,
        debit_cents: 0,
        credit_cents: expense.amount_cents,
        description: "Paid from #{describe_account(expense.paid_from_account_id)}"
      }
    ]

    entry_attrs = %{
      date: expense.date,
      entry_type: "expense",
      reference: "Expense ##{expense.id}",
      description: expense.description
    }

    create_journal_entry_with_lines(entry_attrs, lines)
  end

  @doc """
  Record inventory write-off (waste/shrinkage) as an expense:

    Dr Inventory Waste & Shrinkage Expense (6060)
    Cr Inventory Account (1200/1210/1300)
  """
  def record_inventory_write_off(total_cost_cents, opts \\ []) do
    # 1) Decide which inventory account we're crediting
    {inv_account, inventory_type} =
      cond do
        Keyword.get(opts, :packing, false) -> {get_account_by_code!(@packing_inventory_code), "Packing"}
        Keyword.get(opts, :kitchen, false) -> {get_account_by_code!(@kitchen_inventory_code), "Kitchen"}
        true -> {get_account_by_code!(@ingredients_inventory_code), "Ingredients"}
      end

    waste_expense_account = get_account_by_code!(@inventory_waste_code)

    date = Keyword.get(opts, :write_off_date, Date.utc_today())
    reference = Keyword.get(opts, :reference)

    description =
      Keyword.get(opts, :description,
        "#{inventory_type} inventory write-off (waste/shrinkage)"
      )

    entry_attrs = %{
      date: date,
      entry_type: "expense",
      reference: reference,
      description: description
    }

    lines = [
      %{
        account_id: waste_expense_account.id,
        debit_cents: total_cost_cents,
        credit_cents: 0,
        description: "Inventory waste: #{inventory_type}"
      },
      %{
        account_id: inv_account.id,
        debit_cents: 0,
        credit_cents: total_cost_cents,
        description: "Reduce #{inventory_type} inventory"
      }
    ]

    create_journal_entry_with_lines(entry_attrs, lines)
  end

  @doc """
  Record manual inventory usage as COGS (when not part of an order):

    Dr COGS Account (5000/5010)
    Cr Inventory Account (1200/1210/1300)
  """
  def record_inventory_usage(total_cost_cents, opts \\ []) do
    # 1) Decide which inventory account we're crediting and which COGS account to debit
    {inv_account, cogs_account, inventory_type} =
      cond do
        Keyword.get(opts, :packing, false) ->
          {get_account_by_code!(@packing_inventory_code), get_account_by_code!(@packaging_cogs_code), "Packing"}

        Keyword.get(opts, :kitchen, false) ->
          # Kitchen equipment is typically not COGS, but expense
          # For now, we'll use Other Expenses for kitchen usage
          {get_account_by_code!(@kitchen_inventory_code), get_account_by_code!(@other_expenses_code), "Kitchen"}

        true ->
          {get_account_by_code!(@ingredients_inventory_code), get_account_by_code!(@ingredients_cogs_code), "Ingredients"}
      end

    date = Keyword.get(opts, :usage_date, Date.utc_today())
    reference = Keyword.get(opts, :reference)

    description =
      Keyword.get(opts, :description,
        "Manual #{inventory_type} inventory usage"
      )

    entry_attrs = %{
      date: date,
      entry_type: "expense",
      reference: reference,
      description: description
    }

    lines = [
      %{
        account_id: cogs_account.id,
        debit_cents: total_cost_cents,
        credit_cents: 0,
        description: "#{inventory_type} used (manual)"
      },
      %{
        account_id: inv_account.id,
        debit_cents: 0,
        credit_cents: total_cost_cents,
        description: "Reduce #{inventory_type} inventory"
      }
    ]

    create_journal_entry_with_lines(entry_attrs, lines)
  end

  def update_expense_journal_entry(%Expense{} = expense) do
    reference = "Expense ##{expense.id}"

    journal_entry =
      from(je in JournalEntry, where: je.reference == ^reference)
      |> Repo.one()

    if journal_entry do
      # Update the journal entry
      entry_attrs = %{
        date: expense.date,
        description: expense.description
      }

      lines = [
        %{
          account_id: expense.expense_account_id,
          debit_cents: expense.amount_cents,
          credit_cents: 0,
          description: "Expense: #{expense.description}"
        },
        %{
          account_id: expense.paid_from_account_id,
          debit_cents: 0,
          credit_cents: expense.amount_cents,
          description: "Paid from #{describe_account(expense.paid_from_account_id)}"
        }
      ]

      update_journal_entry_with_lines(journal_entry, entry_attrs, lines)
    else
      # If journal entry doesn't exist, create it
      record_expense(expense)
    end
  end

  # ---------- Money Transfers ----------

  def create_money_transfer(attrs) do
    form_changeset = change_transfer_form(attrs)

    if form_changeset.valid? do
      %{
        from_account_id: from_id,
        to_account_id: to_id,
        date: date,
        amount_pesos: amount_pesos,
        note: note
      } = Ecto.Changeset.apply_changes(form_changeset)

      amount_cents =
        amount_pesos
        |> Decimal.mult(Decimal.new(100))
        |> Decimal.round(0)
        |> Decimal.to_integer()

      Repo.transaction(fn ->
        # 1) Insert the transfer record
        transfer_changeset =
          MoneyTransfer.changeset(%MoneyTransfer{}, %{
            from_account_id: from_id,
            to_account_id: to_id,
            date: date,
            amount_cents: amount_cents,
            note: note
          })

        transfer = Repo.insert!(transfer_changeset)

        # 2) Create the accounting journal entry
        case record_internal_transfer(amount_cents, from_id, to_id,
              date: date,
              note: note,
              reference: "Transfer ##{transfer.id}"
            ) do
          {:ok, _entry} ->
            transfer

          {:error, reason} ->
            IO.inspect(reason, label: "Transfer creation error")
            Repo.rollback(reason)
        end
      end)
      |> case do
        {:ok, transfer} ->
          {:ok, transfer}

        {:error, reason} ->
          {:error,
          form_changeset
          |> Ecto.Changeset.add_error(:base, "Failed to save transfer: #{inspect(reason)}")}
      end
    else
      {:error, form_changeset}
    end
  end

  def list_money_transfers do
    MoneyTransfer
    |> order_by(desc: :date, desc: :inserted_at)
    |> preload([:from_account, :to_account])
    |> Repo.all()
  end

  def get_money_transfer!(id) do
    MoneyTransfer
    |> Repo.get!(id)
    |> Repo.preload([:from_account, :to_account])
  end

  def change_transfer_form(attrs \\ %{}) do
    {%{
      from_account_id: nil,
      to_account_id: nil,
      date: Date.utc_today(),
      amount_pesos: nil,
      note: nil
    },
    %{
      from_account_id: :integer,
      to_account_id: :integer,
      date: :date,
      amount_pesos: :decimal,
      note: :string
    }}
    |> Ecto.Changeset.cast(attrs, [:from_account_id, :to_account_id, :date, :amount_pesos, :note])
    |> Ecto.Changeset.validate_required([
      :from_account_id,
      :to_account_id,
      :date,
      :amount_pesos
    ])
    |> Ecto.Changeset.validate_number(:amount_pesos, greater_than: 0)
    |> validate_different_accounts()
  end

  defp validate_different_accounts(changeset) do
    from_id = Ecto.Changeset.get_field(changeset, :from_account_id)
    to_id   = Ecto.Changeset.get_field(changeset, :to_account_id)

    if from_id && to_id && from_id == to_id do
      Ecto.Changeset.add_error(changeset, :to_account_id, "must be different from source account")
    else
      changeset
    end
  end

  def record_internal_transfer(amount_cents, from_account_id, to_account_id, opts \\ []) do
    date = Keyword.get(opts, :date, Date.utc_today())
    note = Keyword.get(opts, :note, nil)
    ref  = Keyword.get(opts, :reference, nil)

    from_acct = Repo.get!(Account, from_account_id)
    to_acct   = Repo.get!(Account, to_account_id)

    if from_acct.id == to_acct.id do
      raise ArgumentError, "cannot transfer within the same account"
    end

    # Allow only asset/liability for this generic internal transfer helper
    allowed_types = ["asset", "liability"]

    unless from_acct.type in allowed_types and to_acct.type in allowed_types do
      raise ArgumentError,
            "record_internal_transfer supports only asset/liability accounts. " <>
            "Use a dedicated accounting function for revenue/expenses/equity."
    end

    description =
      note ||
        "Transfer from #{from_acct.code} #{from_acct.name} " <>
        "to #{to_acct.code} #{to_acct.name}"

    entry_attrs = %{
      date: date,
      entry_type: "internal_transfer",
      reference: ref,
      description: description
    }

    lines = [
      %{
        account_id: to_acct.id,
        debit_cents: amount_cents,
        credit_cents: 0,
        description: "Transfer from #{from_acct.code} #{from_acct.name}"
      },
      %{
        account_id: from_acct.id,
        debit_cents: 0,
        credit_cents: amount_cents,
        description: "Transfer to #{to_acct.code} #{to_acct.name}"
      }
    ]

    create_journal_entry_with_lines(entry_attrs, lines)
  end

  def update_money_transfer(%MoneyTransfer{} = transfer, attrs) do
    form_changeset = change_transfer_form(attrs)

    if form_changeset.valid? do
      %{
        from_account_id: from_id,
        to_account_id: to_id,
        date: date,
        amount_pesos: amount_pesos,
        note: note
      } = Ecto.Changeset.apply_changes(form_changeset)

      amount_cents =
        amount_pesos
        |> Decimal.mult(Decimal.new(100))
        |> Decimal.round(0)
        |> Decimal.to_integer()

      Repo.transaction(fn ->
        # 1) Find and update the journal entry
        reference = "Transfer ##{transfer.id}"

        journal_entry =
          from(je in JournalEntry, where: je.reference == ^reference)
          |> Repo.one()

        if journal_entry do
          # Update the journal entry
          entry_attrs = %{
            date: date,
            description: note || "Transfer from #{describe_account(from_id)} to #{describe_account(to_id)}"
          }

          from_acct = Repo.get!(Account, from_id)
          to_acct = Repo.get!(Account, to_id)

          lines = [
            %{
              account_id: to_acct.id,
              debit_cents: amount_cents,
              credit_cents: 0,
              description: "Transfer from #{from_acct.code} #{from_acct.name}"
            },
            %{
              account_id: from_acct.id,
              debit_cents: 0,
              credit_cents: amount_cents,
              description: "Transfer to #{to_acct.code} #{to_acct.name}"
            }
          ]

          case update_journal_entry_with_lines(journal_entry, entry_attrs, lines) do
            {:ok, _entry} -> :ok
            {:error, changeset} -> Repo.rollback(changeset)
          end
        end

        # 2) Update the transfer record
        transfer_changeset =
          MoneyTransfer.changeset(transfer, %{
            from_account_id: from_id,
            to_account_id: to_id,
            date: date,
            amount_cents: amount_cents,
            note: note
          })

        case Repo.update(transfer_changeset) do
          {:ok, updated_transfer} -> updated_transfer
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
      |> case do
        {:ok, transfer} -> {:ok, transfer}
        {:error, reason} -> {:error, form_changeset |> Ecto.Changeset.add_error(:base, "Failed to update transfer: #{inspect(reason)}")}
      end
    else
      {:error, form_changeset}
    end
  end

  def delete_money_transfer(%MoneyTransfer{} = transfer) do
    Repo.transaction(fn ->
      # Find and delete the related journal entry
      reference = "Transfer ##{transfer.id}"

      journal_entry =
        from(je in JournalEntry, where: je.reference == ^reference)
        |> Repo.one()

      if journal_entry do
        Repo.delete!(journal_entry)
      end

      # Delete the transfer
      Repo.delete!(transfer)
    end)
  end

  # ---------- Helpers for totals / formatting ----------

  # Adds :total_cents and :total_amount_formatted to entries
  defp put_totals(%JournalEntry{} = entry) do
    total =
      Enum.reduce(entry.journal_lines || [], 0, fn line, acc ->
        acc + (line.debit_cents || 0) - (line.credit_cents || 0)
      end)
      |> abs()

    entry
    |> Map.put(:total_cents, total)
    |> Map.put(:total_amount_formatted, format_cents(total))
  end

  def format_cents(nil), do: "0.00"

  def format_cents(cents) when is_integer(cents) do
    sign = if cents < 0, do: "-", else: ""
    cents = abs(cents)

    pesos = div(cents, 100)
    centavos =
      cents
      |> rem(100)
      |> Integer.to_string()
      |> String.pad_leading(2, "0")

    "#{sign}$#{pesos}.#{centavos}"
  end

  defp describe_account(id) do
    case Repo.get(Account, id) do
      nil -> "Account #{id}"
      acc -> "#{acc.code} – #{acc.name}"
    end
  end

  def shipping_fee_cents do
    case Repo.get_by(Product, sku: @shipping_product_sku) do
      nil -> 0
      %Product{price_cents: cents} -> cents || 0
    end
  end



  # ---------- Financial Statements ----------

  @doc """
  Profit & Loss for a period.

  Returns a map with:
    - revenue_accounts
    - cogs_accounts
    - operating_expense_accounts
    - total_revenue_cents
    - total_cogs_cents
    - gross_profit_cents
    - total_opex_cents
    - operating_income_cents
    - net_income_cents
  """
  def profit_and_loss(start_date, end_date) do

    # 1) Aggregate debits & credits per account in the period
    query =
      from je in JournalEntry,
        join: jl in assoc(je, :journal_lines),
        join: a in assoc(jl, :account),
        where: je.date >= ^start_date and je.date <= ^end_date,
        group_by: [a.id, a.code, a.name, a.type, a.normal_balance],
        select: {
          a.id,
          a.code,
          a.name,
          a.type,
          a.normal_balance,
          coalesce(sum(jl.debit_cents), 0),
          coalesce(sum(jl.credit_cents), 0)
        }

    rows =
      query
      |> Repo.all()
      |> Enum.map(fn {account_id, code, name, type, normal_balance, debit_cents, credit_cents} ->
        %{
          account_id: account_id,
          code: code,
          name: name,
          type: type,
          normal_balance: normal_balance,
          debit_cents: debit_cents,
          credit_cents: credit_cents
        }
      end)

    # 2) Compute net_cents for each account based on normal_balance
    enriched =
      Enum.map(rows, fn row ->
        debits = row.debit_cents || 0
        credits = row.credit_cents || 0

        net =
          case row.normal_balance do
            "debit" -> debits - credits
            "credit" -> credits - debits
            _ -> credits - debits
          end

        Map.put(row, :net_cents, net)
      end)

    # 3) Split by type
    revenue_accounts = Enum.filter(enriched, &(&1.type == "revenue"))
    expense_accounts = Enum.filter(enriched, &(&1.type == "expense"))

    # 4) Split expenses into COGS vs Opex using @cogs_codes
    {cogs_accounts, operating_expense_accounts} =
      Enum.split_with(expense_accounts, fn acc ->
        acc.code == @ingredients_cogs_code
      end)

    total_revenue_cents = Enum.reduce(revenue_accounts, 0, fn acc, sum -> sum + acc.net_cents end)
    total_cogs_cents = Enum.reduce(cogs_accounts, 0, fn acc, sum -> sum + acc.net_cents end)
    total_opex_cents = Enum.reduce(operating_expense_accounts, 0, fn acc, sum -> sum + acc.net_cents end)

    gross_profit_cents = total_revenue_cents - total_cogs_cents
    operating_income_cents = gross_profit_cents - total_opex_cents
    net_income_cents = operating_income_cents

    # Calculate margins
    gross_margin_percent =
      if total_revenue_cents > 0 do
        Float.round(gross_profit_cents / total_revenue_cents * 100, 2)
      else
        0.0
      end

    operating_margin_percent =
      if total_revenue_cents > 0 do
        Float.round(operating_income_cents / total_revenue_cents * 100, 2)
      else
        0.0
      end

    net_margin_percent =
      if total_revenue_cents > 0 do
        Float.round(net_income_cents / total_revenue_cents * 100, 2)
      else
        0.0
      end

    # Get revenue breakdown by product
    revenue_by_product = revenue_by_product(start_date, end_date)

    # Get COGS breakdown by product
    cogs_by_product = cogs_by_product(start_date, end_date)

    %{
      start_date: start_date,
      end_date: end_date,
      revenue_accounts: revenue_accounts,
      cogs_accounts: cogs_accounts,
      operating_expense_accounts: operating_expense_accounts,
      total_revenue_cents: total_revenue_cents,
      total_cogs_cents: total_cogs_cents,
      gross_profit_cents: gross_profit_cents,
      total_opex_cents: total_opex_cents,
      operating_income_cents: operating_income_cents,
      net_income_cents: net_income_cents,
      gross_margin_percent: gross_margin_percent,
      operating_margin_percent: operating_margin_percent,
      net_margin_percent: net_margin_percent,
      revenue_by_product: revenue_by_product,
      cogs_by_product: cogs_by_product
    }
  end

  def profit_and_loss_monthly(months_back \\ 5) do
    # "months_back = 5" → last 6 months including current
    today = Date.utc_today()
    {year, month, _day} = Date.to_erl(today)

    months =
      0..months_back
      |> Enum.map(fn offset ->
        {y, m} = shift_year_month(year, month, -offset)
        start_date = %Date{year: y, month: m, day: 1}
        end_date   = end_of_month(start_date)
        {start_date, end_date}
      end)
      |> Enum.reverse()

    Enum.map(months, fn {start_date, end_date} ->
      summary = profit_and_loss(start_date, end_date)

      # Reuse your summary map and just tag it with a month label + boundaries
      summary
      |> Map.put(:label, "#{start_date.year}-#{pad2(start_date.month)}")
      |> Map.put(:month_start, start_date)
      |> Map.put(:month_end, end_date)
    end)
  end

  # ---- helpers for monthly calc ----

  defp shift_year_month(year, month, delta_months) do
    total = year * 12 + (month - 1) + delta_months
    new_year = div(total, 12)
    new_month = rem(total, 12) + 1
    {new_year, new_month}
  end

  defp end_of_month(%Date{} = date) do
    {y, m, _} = Date.to_erl(date)
    {ny, nm} = shift_year_month(y, m, 1)
    first_next = %Date{year: ny, month: nm, day: 1}
    Date.add(first_next, -1)
  end

  defp pad2(int) when is_integer(int) and int < 10, do: "0#{int}"
  defp pad2(int) when is_integer(int), do: Integer.to_string(int)

  # Get revenue breakdown by product
  defp revenue_by_product(start_date, end_date) do
    shipping_fee = shipping_fee_cents()

    from(o in Order,
      join: p in assoc(o, :product),
      where: o.delivery_date >= ^start_date and o.delivery_date <= ^end_date and o.status == "delivered",
      group_by: [p.id, p.name, p.sku],
      select: %{
        product_id: p.id,
        product_name: p.name,
        product_sku: p.sku,
        revenue_cents: fragment("SUM(?) + SUM(CASE WHEN ? THEN ? ELSE 0 END)", p.price_cents, o.customer_paid_shipping, ^shipping_fee)
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
  defp cogs_by_product(start_date, end_date) do
    # Get all delivered orders in the period with their products
    orders =
      from(o in Order,
        join: p in assoc(o, :product),
        where: o.delivery_date >= ^start_date and o.delivery_date <= ^end_date and o.status == "delivered",
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

        # Add the first reference pattern with where, then use or_where for the rest
        query =
          case reference_patterns do
            [] ->
              base_query
            [first_pattern] ->
              base_query
              |> where([je], ilike(je.reference, ^first_pattern))
            [first_pattern | rest_patterns] when rest_patterns != [] ->
              # Start with first pattern, then reduce over the rest
              initial_query = base_query |> where([je], ilike(je.reference, ^first_pattern))
              Enum.reduce(rest_patterns, initial_query, fn pattern, acc_q ->
                or_where(acc_q, [je], ilike(je.reference, ^pattern))
              end)
            _ ->
              # Fallback - should not happen but just in case
              base_query
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

  def balance_sheet(as_of_date) do

    # 1) Aggregate balances by account (assets, liabilities, equity)
    rows =
      from a in Account,
        where: a.type in ["asset", "liability", "equity"],
        left_join: jl in JournalLine,
          on: jl.account_id == a.id,
        left_join: je in JournalEntry,
          on: jl.journal_entry_id == je.id and je.date <= ^as_of_date,
        group_by: [a.id, a.code, a.name, a.type, a.normal_balance],
        select: %{
          account: a,
          debit_cents: coalesce(sum(jl.debit_cents), 0),
          credit_cents: coalesce(sum(jl.credit_cents), 0)
        }

    base =
      rows
      |> Repo.all()
      |> Enum.reduce(
        %{
          assets: [],
          liabilities: [],
          equity: [],
          total_assets_cents: 0,
          total_liabilities_cents: 0,
          total_equity_cents: 0
        },
        fn %{account: account, debit_cents: debit, credit_cents: credit}, acc ->
          amount_cents =
            case account.normal_balance do
              "debit" -> debit - credit
              "credit" -> credit - debit
              _ -> debit - credit
            end

          case account.type do
            "asset" ->
              %{acc |
                assets: acc.assets ++ [%{account: account, amount_cents: amount_cents}],
                total_assets_cents: acc.total_assets_cents + amount_cents
              }

            "liability" ->
              %{acc |
                liabilities: acc.liabilities ++ [%{account: account, amount_cents: amount_cents}],
                total_liabilities_cents: acc.total_liabilities_cents + amount_cents
              }

            "equity" ->
              %{acc |
                equity: acc.equity ++ [%{account: account, amount_cents: amount_cents}],
                total_equity_cents: acc.total_equity_cents + amount_cents
              }
          end
        end
      )

    # 2) Compute Net Income up to as_of_date (all-time P&L until that date)
    pnl = profit_and_loss(~D[2000-01-01], as_of_date)
    net_income_cents = pnl.net_income_cents

    # 3) Compute RHS: Liabilities + Equity + Net Income
    rhs_total_cents =
      base.total_liabilities_cents +
        base.total_equity_cents +
        net_income_cents

    balance_diff_cents = base.total_assets_cents - rhs_total_cents

    base
    |> Map.put(:net_income_cents, net_income_cents)
    |> Map.put(:liabilities_plus_equity_plus_income_cents, rhs_total_cents)
    |> Map.put(:balance_diff_cents, balance_diff_cents)
  end


  # ---------- Capital Contributions ----------

  def record_capital_contribution(%CapitalContribution{} = contrib) do
    contrib = Repo.preload(contrib, [:partner, :cash_account])

    cash_account =
      case contrib.cash_account do
        %Account{} = acc -> acc
        _ -> get_account_by_code!(@cash_code) # fallback, just in case
      end

    equity_account = get_account_by_code!(@owners_equity_code)
    amount        = contrib.amount_cents

    case contrib.direction do
      "in"  -> record_owner_investment(contrib, cash_account, equity_account, amount)
      "out" -> record_owner_withdrawal(contrib, cash_account, equity_account, amount)
      _     -> {:error, :unknown_direction}
    end
  end

  defp record_owner_investment(contrib, cash_account, equity_account, amount_cents) do
    entry_attrs = %{
      date: contrib.date,
      entry_type: "investment",
      reference: "Capital contribution ##{contrib.id}",
      description:
        contrib.note ||
          "Owner investment by #{contrib.partner && contrib.partner.name || "Partner"}"
    }

    lines = [
      %{
        account_id: cash_account.id,
        debit_cents: amount_cents,
        credit_cents: 0,
        description: "Cash received from partner"
      },
      %{
        account_id: equity_account.id,
        debit_cents: 0,
        credit_cents: amount_cents,
        description: "Increase in owner's equity"
      }
    ]

    create_journal_entry_with_lines(entry_attrs, lines)
  end

  defp record_owner_withdrawal(contrib, cash_account, equity_account, amount_cents) do
    entry_attrs = %{
      date: contrib.date,
      entry_type: "withdrawal",
      reference: "Capital withdrawal ##{contrib.id}",
      description:
        contrib.note ||
          "Owner withdrawal by #{contrib.partner && contrib.partner.name || "Partner"}"
    }

    lines = [
      %{
        account_id: equity_account.id,
        debit_cents: amount_cents,
        credit_cents: 0,
        description: "Decrease in owner's equity"
      },
      %{
        account_id: cash_account.id,
        debit_cents: 0,
        credit_cents: amount_cents,
        description: "Cash paid to partner"
      }
    ]

    create_journal_entry_with_lines(entry_attrs, lines)
  end
end
