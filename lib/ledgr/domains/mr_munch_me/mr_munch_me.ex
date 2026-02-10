defmodule Ledgr.Domains.MrMunchMe do
  @moduledoc """
  MrMunchMe domain configuration.

  A bakery-style business that sells baked goods, manages ingredient
  inventory, and recognizes revenue on order delivery.
  """

  @behaviour Ledgr.Domain.DomainConfig
  @behaviour Ledgr.Domain.RevenueHandler
  @behaviour Ledgr.Domain.DashboardProvider

  alias Ledgr.Core.Accounting

  # ── DomainConfig callbacks ──────────────────────────────────────────

  @impl Ledgr.Domain.DomainConfig
  def name, do: "MrMunchMe"

  @impl Ledgr.Domain.DomainConfig
  def account_codes do
    %{
      ar: "1100",
      cash: "1000",
      ingredients_inventory: "1200",
      packing_inventory: "1210",
      wip_inventory: "1220",
      kitchen_inventory: "1300",
      customer_deposits: "2200",
      sales: "4000",
      sales_discounts: "4010",
      owners_equity: "3000",
      retained_earnings: "3050",
      owners_drawings: "3100",
      ingredients_cogs: "5000",
      packaging_cogs: "5010",
      inventory_waste: "6060",
      samples_gifts: "6070",
      other_expenses: "6099",
      shipping_product_sku: "ENVIO"
    }
  end

  @impl Ledgr.Domain.DomainConfig
  def journal_entry_types do
    [
      {"Order Created", "order_created"},
      {"Order in Prep", "order_in_prep"},
      {"Order Delivered", "order_delivered"},
      {"Order Payment", "order_payment"}
    ]
  end

  @impl Ledgr.Domain.DomainConfig
  def menu_items do
    [
      %{group: "Main Menu", items: [
        %{label: "Dashboard", path: "/", icon: :dashboard},
        %{label: "All Orders", path: "/orders", icon: :orders},
        %{label: "Order Calendar", path: "/orders/calendar", icon: :calendar},
        %{label: "Inventory", path: "/inventory", icon: :inventory},
        %{label: "Shopping List", path: "/inventory/requirements", icon: :shopping},
        %{label: "Expenses", path: "/expenses", icon: :expenses}
      ]},
      %{group: "Materials", items: [
        %{label: "Product List", path: "/products", icon: :products},
        %{label: "Ingredient List", path: "/ingredients", icon: :ingredients},
        %{label: "Recepies", path: "/recipes", icon: :recipes}
      ]}
    ]
  end

  @impl Ledgr.Domain.DomainConfig
  def seed_file, do: "priv/repo/seeds/mr_munch_me_seeds.exs"

  # ── RevenueHandler callbacks ────────────────────────────────────────

  @impl Ledgr.Domain.RevenueHandler
  def handle_status_change(order, new_status) do
    Accounting.handle_order_status_change(order, new_status)
  end

  @impl Ledgr.Domain.RevenueHandler
  def record_payment(payment) do
    Accounting.record_order_payment(payment)
  end

  @impl Ledgr.Domain.RevenueHandler
  def revenue_breakdown(start_date, end_date) do
    Accounting.revenue_by_product(start_date, end_date)
  end

  @impl Ledgr.Domain.RevenueHandler
  def cogs_breakdown(start_date, end_date) do
    Accounting.cogs_by_product(start_date, end_date)
  end

  # ── DashboardProvider callbacks ─────────────────────────────────────

  @impl Ledgr.Domain.DashboardProvider
  def dashboard_metrics(start_date, end_date) do
    Ledgr.Core.Reporting.dashboard_metrics(start_date, end_date)
  end
end
