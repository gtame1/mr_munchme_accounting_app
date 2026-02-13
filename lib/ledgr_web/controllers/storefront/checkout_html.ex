defmodule LedgrWeb.Storefront.CheckoutHTML do
  use LedgrWeb, :html

  embed_templates "checkout_html/*"

  def format_price(cents) when is_integer(cents) do
    pesos = cents / 100
    "$#{:erlang.float_to_binary(pesos, decimals: 2)} MXN"
  end

  def format_price(_), do: ""
end
