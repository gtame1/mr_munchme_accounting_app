defmodule LedgrWeb.Router do
  use LedgrWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {LedgrWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # ── Core routes (always present) ──────────────────────────────────────
  scope "/", LedgrWeb do
    pipe_through :browser

    get "/", ReportController, :dashboard

    resources "/transactions", TransactionController, only: [:index, :new, :create, :show]
    get "/account-transactions", AccountTransactionController, :index

    get "/reports/pnl", ReportController, :pnl
    get "/reports/balance_sheet", ReportController, :balance_sheet
    post "/reports/year_end_close", ReportController, :year_end_close
    get "/reports/unit_economics", ReportController, :unit_economics
    get "/reports/unit_economics_list", ReportController, :unit_economics_list
    get "/reports/cash_flow", ReportController, :cash_flow
    get "/reports/diagnostics", ReportController, :diagnostics
    post "/reports/diagnostics", ReportController, :diagnostics

    get "/reconciliation/accounting", ReconciliationController, :accounting_index
    post "/reconciliation/accounting/adjust", ReconciliationController, :accounting_adjust
    post "/reconciliation/accounting/reconcile_all", ReconciliationController, :accounting_reconcile_all
    get "/reconciliation/inventory", ReconciliationController, :inventory_index
    post "/reconciliation/inventory/adjust", ReconciliationController, :inventory_adjust
    post "/reconciliation/inventory/reconcile_all", ReconciliationController, :inventory_reconcile_all
    post "/reconciliation/inventory/quick_transfer", ReconciliationController, :inventory_quick_transfer

    resources "/customers", CustomerController

    get  "/investments",        InvestmentController, :index
    get  "/investments/new",    InvestmentController, :new
    get  "/investments/withdrawal",    InvestmentController, :new_withdrawal
    post "/investments",        InvestmentController, :create
    post "/investments/create-withdrawal", InvestmentController, :create_withdrawal

    resources "/transfers", TransferController

    resources "/expenses", ExpenseController, only: [:index, :new, :create, :show, :edit, :update, :delete]
  end

  # ── MrMunchMe domain routes ──────────────────────────────────────────
  if Application.compile_env(:ledgr, :domain) == Ledgr.Domains.MrMunchMe do
    scope "/", LedgrWeb do
      pipe_through :browser

      get "/orders/calendar", Domains.MrMunchMe.OrderController, :calendar
      resources "/orders", Domains.MrMunchMe.OrderController, only: [:index, :show, :new, :create, :edit, :update]
      post "/orders/:id/status", Domains.MrMunchMe.OrderController, :update_status
      post "/orders/:id/ingredients", Domains.MrMunchMe.OrderController, :update_ingredients
      get "/orders/:id/payments/new", Domains.MrMunchMe.OrderController, :new_payment
      post "/orders/:id/payments", Domains.MrMunchMe.OrderController, :create_payment

      resources "/order_payments", Domains.MrMunchMe.OrderPaymentController, only: [:index, :show, :edit, :update, :delete]

      get "/inventory", Domains.MrMunchMe.InventoryController, :index
      get  "/inventory/purchases/new", Domains.MrMunchMe.InventoryController, :new_purchase
      post "/inventory/purchases",     Domains.MrMunchMe.InventoryController, :create_purchase
      get  "/inventory/purchases/:id/edit", Domains.MrMunchMe.InventoryController, :edit_purchase
      put  "/inventory/purchases/:id", Domains.MrMunchMe.InventoryController, :update_purchase
      delete "/inventory/purchases/:id", Domains.MrMunchMe.InventoryController, :delete_purchase
      post "/inventory/purchases/:id/return", Domains.MrMunchMe.InventoryController, :return_purchase
      get  "/inventory/movements/new", Domains.MrMunchMe.InventoryController, :new_movement
      post "/inventory/movements",     Domains.MrMunchMe.InventoryController, :create_movement
      get  "/inventory/movements/:id/edit", Domains.MrMunchMe.InventoryController, :edit_movement
      put  "/inventory/movements/:id", Domains.MrMunchMe.InventoryController, :update_movement
      delete "/inventory/movements/:id", Domains.MrMunchMe.InventoryController, :delete_movement
      get "/inventory/requirements", Domains.MrMunchMe.InventoryController, :requirements

      resources "/products", Domains.MrMunchMe.ProductController, only: [:index, :new, :create, :edit, :update, :delete]
      resources "/ingredients", Domains.MrMunchMe.IngredientController, only: [:index, :new, :create, :edit, :update, :delete]
      resources "/recipes", Domains.MrMunchMe.RecipeController, only: [:index, :new, :create, :show, :edit, :delete]
      post "/recipes/new_version/:id", Domains.MrMunchMe.RecipeController, :create_new_version
    end
  end

  # ── API endpoints ────────────────────────────────────────────────────
  scope "/api", LedgrWeb do
    pipe_through :api

    # Products
    get "/products", ApiController, :list_products
    get "/products/:id", ApiController, :show_product

    # Orders
    get "/orders", ApiController, :list_orders
    get "/orders/:id", ApiController, :show_order

    # Customers
    get "/customers", ApiController, :list_customers
    get "/customers/check_phone/:phone", ApiController, :check_customer_phone
    get "/customers/:id", ApiController, :show_customer

    # Inventory
    get "/ingredients", ApiController, :list_ingredients
    get "/ingredients/:id", ApiController, :show_ingredient
    get "/stock", ApiController, :list_stock
    get "/locations", ApiController, :list_locations

    # Accounting
    get "/accounts", ApiController, :list_accounts
    get "/accounts/:id", ApiController, :show_account
    get "/journal_entries", ApiController, :list_journal_entries
    get "/journal_entries/:id", ApiController, :show_journal_entry

    # Reports
    get "/reports/balance_sheet", ApiController, :balance_sheet
    get "/reports/profit_and_loss", ApiController, :profit_and_loss
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:ledgr, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: LedgrWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
