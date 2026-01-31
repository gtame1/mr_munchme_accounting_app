defmodule MrMunchMeAccountingAppWeb.Router do
  use MrMunchMeAccountingAppWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MrMunchMeAccountingAppWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", MrMunchMeAccountingAppWeb do
    pipe_through :browser


    resources "/transactions", TransactionController, only: [:index, :new, :create, :show]
    get "/account-transactions", AccountTransactionController, :index

    get "/orders/calendar", OrderController, :calendar
    resources "/orders", OrderController, only: [:index, :show, :new, :create, :edit, :update]
    post "/orders/:id/status", OrderController, :update_status
    post "/orders/:id/ingredients", OrderController, :update_ingredients
    get "/orders/:id/payments/new", OrderController, :new_payment
    post "/orders/:id/payments", OrderController, :create_payment

    resources "/order_payments", OrderPaymentController, only: [:index, :show, :edit, :update, :delete]

    get "/", ReportController, :dashboard
    get "/reports/pnl", ReportController, :pnl
    get "/reports/balance_sheet", ReportController, :balance_sheet
    get "/reports/unit_economics", ReportController, :unit_economics
    get "/reports/unit_economics_list", ReportController, :unit_economics_list
    get "/reports/cash_flow", ReportController, :cash_flow

    get "/reconciliation/accounting", ReconciliationController, :accounting_index
    post "/reconciliation/accounting/adjust", ReconciliationController, :accounting_adjust
    get "/reconciliation/inventory", ReconciliationController, :inventory_index
    post "/reconciliation/inventory/adjust", ReconciliationController, :inventory_adjust

    get "/reports/inventory_verification", ReportController, :inventory_verification
    post "/reports/inventory_verification", ReportController, :inventory_verification

    get "/inventory", InventoryController, :index
    get  "/inventory/purchases/new", InventoryController, :new_purchase
    post "/inventory/purchases",     InventoryController, :create_purchase
    get  "/inventory/purchases/:id/edit", InventoryController, :edit_purchase
    put  "/inventory/purchases/:id", InventoryController, :update_purchase
    delete "/inventory/purchases/:id", InventoryController, :delete_purchase
    post "/inventory/purchases/:id/return", InventoryController, :return_purchase
    get  "/inventory/movements/new", InventoryController, :new_movement
    post "/inventory/movements",     InventoryController, :create_movement
    get  "/inventory/movements/:id/edit", InventoryController, :edit_movement
    put  "/inventory/movements/:id", InventoryController, :update_movement
    delete "/inventory/movements/:id", InventoryController, :delete_movement
    get "/inventory/requirements", InventoryController, :requirements

    resources "/products", ProductController, only: [:index, :new, :create, :edit, :update, :delete]
    resources "/customers", CustomerController
    resources "/ingredients", IngredientController, only: [:index, :new, :create, :edit, :update, :delete]
    resources "/recipes", RecipeController, only: [:index, :new, :create, :show, :edit, :delete]
    post "/recipes/new_version/:id", RecipeController, :create_new_version

    get  "/investments",        InvestmentController, :index
    get  "/investments/new",    InvestmentController, :new
    get  "/investments/withdrawal",    InvestmentController, :new_withdrawal
    post "/investments",        InvestmentController, :create
    post "/investments/create-withdrawal", InvestmentController, :create_withdrawal

    resources "/transfers", TransferController

    resources "/expenses", ExpenseController, only: [:index, :new, :create, :show, :edit, :update, :delete]
  end

  # API endpoints
  scope "/api", MrMunchMeAccountingAppWeb do
    pipe_through :api

    # Products
    get "/products", ApiController, :list_products
    get "/products/:id", ApiController, :show_product

    # Orders
    get "/orders", ApiController, :list_orders
    get "/orders/:id", ApiController, :show_order

    # Customers
    get "/customers", ApiController, :list_customers
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
  if Application.compile_env(:mr_munch_me_accounting_app, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: MrMunchMeAccountingAppWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
