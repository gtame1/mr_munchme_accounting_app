defmodule Ledgr.Domain.DomainConfig do
  @moduledoc """
  Behaviour for domain-specific configuration.

  Each business type (MrMunchMe, Viaxe, etc.) implements this behaviour
  to provide its name, account codes, journal entry types, and navigation.
  """

  @doc "Human-readable name of the business type (e.g., \"MrMunchMe\")."
  @callback name() :: String.t()

  @doc """
  Map of semantic account code keys to chart-of-accounts codes.

  Example:
      %{
        ar: "1100",
        sales: "4000",
        customer_deposits: "2200",
        ingredients_inventory: "1200",
        ...
      }
  """
  @callback account_codes() :: map()

  @doc """
  Domain-specific journal entry types to be merged with core types.

  Returns a list of {label, value} tuples, e.g.:
      [{"Order in Prep", "order_in_prep"}, {"Order Delivered", "order_delivered"}]
  """
  @callback journal_entry_types() :: [{String.t(), String.t()}]

  @doc """
  Navigation menu items for the domain.

  Returns a list of maps with :label, :path, and :icon keys.
  """
  @callback menu_items() :: [%{label: String.t(), path: String.t(), icon: atom()}]

  @doc """
  Path to the domain-specific seed file, relative to the project root.

  Returns nil if no domain-specific seeds are needed.
  """
  @callback seed_file() :: String.t() | nil

  @doc """
  Returns true if the given customer has active dependencies in this domain.

  Used by the Customers context to prevent deletion of customers that have
  active orders, bookings, or other domain-specific records.
  """
  @callback has_active_dependencies?(customer_id :: integer()) :: boolean()

  @doc """
  URL slug for the domain, used in path prefixes.

  Example: "mr-munch-me" → routes at /app/mr-munch-me/...
  """
  @callback slug() :: String.t()

  @doc """
  Full URL path prefix for the domain.

  Example: "/app/mr-munch-me"
  """
  @callback path_prefix() :: String.t()

  @doc """
  Emoji or short string used as a logo in the sidebar.
  """
  @callback logo() :: String.t()

  @doc """
  Theme configuration for the domain.

  Returns a map of CSS custom property values for per-domain theming.
  """
  @callback theme() :: %{
              sidebar_bg: String.t(),
              sidebar_text: String.t(),
              sidebar_hover: String.t(),
              primary: String.t(),
              primary_soft: String.t(),
              accent: String.t()
            }
end
