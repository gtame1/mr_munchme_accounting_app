defmodule Ledgr.Domain.RevenueHandler do
  @moduledoc """
  Behaviour for domain-specific revenue recognition.

  Each business type implements this to define how revenue is recognized
  and recorded in the general ledger. A bakery recognizes revenue on
  delivery; a travel agency might recognize it on trip completion.
  """

  @doc "Called when a domain entity changes status (e.g., order delivered, booking confirmed)."
  @callback handle_status_change(entity :: struct(), new_status :: String.t()) ::
              :ok | {:ok, any()} | {:error, any()}

  @doc "Called when a payment is received for a domain entity."
  @callback record_payment(payment :: struct()) :: {:ok, any()} | {:error, any()}

  @doc "Returns revenue breakdown for P&L enrichment within a date range."
  @callback revenue_breakdown(Date.t(), Date.t()) :: [map()]

  @doc "Returns COGS/cost breakdown for P&L enrichment within a date range."
  @callback cogs_breakdown(Date.t(), Date.t()) :: [map()]
end
