defmodule LedgrWeb.Domains.Viaxe.DocumentController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.Viaxe.TravelDocuments

  def index(conn, _params) do
    passports = TravelDocuments.list_passports()
    visas = TravelDocuments.list_visas()
    loyalty_programs = TravelDocuments.list_loyalty_programs()

    render(conn, :index,
      passports: passports,
      visas: visas,
      loyalty_programs: loyalty_programs,
      today: Date.utc_today()
    )
  end
end

defmodule LedgrWeb.Domains.Viaxe.DocumentHTML do
  use LedgrWeb, :html

  alias Ledgr.Domains.Viaxe.Customers.Customer

  embed_templates "document_html/*"

  def full_name(customer), do: Customer.full_name(customer)

  # Returns :expired, :expiring_soon, or :ok
  def expiry_status(nil, _today), do: :ok
  def expiry_status(expiry_date, today) do
    cond do
      Date.compare(expiry_date, today) == :lt        -> :expired
      Date.diff(expiry_date, today) <= 180            -> :expiring_soon
      true                                            -> :ok
    end
  end
end
