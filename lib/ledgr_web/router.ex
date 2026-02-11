defmodule LedgrWeb.Router do
  use LedgrWeb, :router

  import LedgrWeb.Router.CoreRoutes

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {LedgrWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug LedgrWeb.Plugs.DomainPlug
  end

  pipeline :require_auth do
    plug LedgrWeb.Plugs.AuthPlug
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # ── Landing page (no domain context) ────────────────────────────────
  scope "/", LedgrWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # ── MrMunchMe: public auth routes ──────────────────────────────────
  scope "/app/mr-munch-me", LedgrWeb do
    pipe_through :browser

    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete
  end

  # ── MrMunchMe: protected routes ────────────────────────────────────
  scope "/app/mr-munch-me", LedgrWeb do
    pipe_through [:browser, :require_auth]

    core_routes()

    # MrMunchMe-specific routes
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

  # ── Viaxe: public auth routes ──────────────────────────────────────
  scope "/app/viaxe", LedgrWeb do
    pipe_through :browser

    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete
  end

  # ── Viaxe: protected routes ────────────────────────────────────────
  scope "/app/viaxe", LedgrWeb do
    pipe_through [:browser, :require_auth]

    core_routes()

    # Viaxe-specific routes
    resources "/bookings", Domains.Viaxe.BookingController, only: [:index, :show, :new, :create, :edit, :update, :delete]
    post "/bookings/:id/status", Domains.Viaxe.BookingController, :update_status

    resources "/services", Domains.Viaxe.ServiceController, only: [:index, :new, :create, :edit, :update, :delete]

    resources "/suppliers", Domains.Viaxe.SupplierController
  end

  # ── API endpoints (core) ─────────────────────────────────────────────
  scope "/api", LedgrWeb do
    pipe_through :api

    # Customers
    get "/customers", ApiController, :list_customers
    get "/customers/check_phone/:phone", ApiController, :check_customer_phone
    get "/customers/:id", ApiController, :show_customer

    # Accounting
    get "/accounts", ApiController, :list_accounts
    get "/accounts/:id", ApiController, :show_account
    get "/journal_entries", ApiController, :list_journal_entries
    get "/journal_entries/:id", ApiController, :show_journal_entry

    # Reports
    get "/reports/balance_sheet", ApiController, :balance_sheet
    get "/reports/profit_and_loss", ApiController, :profit_and_loss
  end

  # ── API endpoints (MrMunchMe domain) ───────────────────────────────
  scope "/api/mr-munch-me", LedgrWeb do
    pipe_through :api

    # Products
    get "/products", Domains.MrMunchMe.ApiController, :list_products
    get "/products/:id", Domains.MrMunchMe.ApiController, :show_product

    # Orders
    get "/orders", Domains.MrMunchMe.ApiController, :list_orders
    get "/orders/:id", Domains.MrMunchMe.ApiController, :show_order

    # Inventory
    get "/ingredients", Domains.MrMunchMe.ApiController, :list_ingredients
    get "/ingredients/:id", Domains.MrMunchMe.ApiController, :show_ingredient
    get "/stock", Domains.MrMunchMe.ApiController, :list_stock
    get "/locations", Domains.MrMunchMe.ApiController, :list_locations
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:ledgr, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: LedgrWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
