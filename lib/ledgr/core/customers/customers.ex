defmodule Ledgr.Core.Customers do
  @moduledoc """
  The Customers context.
  """

  import Ecto.Query, warn: false
  alias Ledgr.Repo

  alias Ledgr.Core.Customers.Customer

  @doc """
  Returns the list of customers.

  ## Examples

      iex> list_customers()
      [%Customer{}, ...]

  """
  def list_customers do
    Repo.all(Customer)
  end

  @doc """
  Gets a single customer.

  Raises `Ecto.NoResultsError` if the Customer does not exist.

  ## Examples

      iex> get_customer!(123)
      %Customer{}

      iex> get_customer!(456)
      ** (Ecto.NoResultsError)

  """
  def get_customer!(id), do: Repo.get!(Customer, id)

  @doc """
  Gets a single customer by phone number. Returns nil if not found.
  """
  def get_customer_by_phone(phone) do
    Repo.get_by(Customer, phone: phone)
  end

  @doc """
  Creates a customer.

  ## Examples

      iex> create_customer(%{field: value})
      {:ok, %Customer{}}

      iex> create_customer(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_customer(attrs) do
    %Customer{}
    |> Customer.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a customer.

  ## Examples

      iex> update_customer(customer, %{field: new_value})
      {:ok, %Customer{}}

      iex> update_customer(customer, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_customer(%Customer{} = customer, attrs) do
    customer
    |> Customer.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a customer.
  Returns {:error, :has_active_orders} if the customer has active orders.

  ## Examples

      iex> delete_customer(customer)
      {:ok, %Customer{}}

      iex> delete_customer(customer_with_orders)
      {:error, :has_active_orders}
  """
  def delete_customer(%Customer{} = customer) do
    domain = Ledgr.Domain.current()

    has_deps =
      if domain do
        domain.has_active_dependencies?(customer.id)
      else
        false
      end

    if has_deps do
      {:error, :has_active_orders}
    else
      Repo.delete(customer)
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking customer changes.

  ## Examples

      iex> change_customer(customer)
      %Ecto.Changeset{data: %Customer{}}

  """
  def change_customer(%Customer{} = customer, attrs \\ %{}) do
    Customer.changeset(customer, attrs)
  end

  @doc """
  Finds a customer by phone number, or creates a new one if not found.
  If customer exists and doesn't have a delivery_address but one is provided in attrs,
  updates the customer with the delivery_address.
  """
  def find_or_create_by_phone(phone, attrs \\ %{}) do
    case Repo.get_by(Customer, phone: phone) do
      nil ->
        # Create new customer with all provided attrs
        create_customer(Map.merge(%{phone: phone}, attrs))

      customer ->
        # If customer exists but doesn't have delivery_address, and one is provided, update it
        delivery_address = Map.get(attrs, :delivery_address) || Map.get(attrs, "delivery_address")

        if delivery_address && String.trim(delivery_address) != "" &&
             (!customer.delivery_address || String.trim(customer.delivery_address) == "") do
          case update_customer(customer, %{delivery_address: delivery_address}) do
            {:ok, updated_customer} -> {:ok, updated_customer}
            {:error, _changeset} -> {:ok, customer}
          end
        else
          {:ok, customer}
        end
    end
  end

  @doc """
  Returns a list of customer options for select dropdowns.
  Format: [{name (phone), id}]
  """
  def customer_select_options do
    list_customers()
    |> Enum.map(fn customer ->
      label = if customer.email && customer.email != "" do
        "#{customer.name} (#{customer.phone}) - #{customer.email}"
      else
        "#{customer.name} (#{customer.phone})"
      end
      {label, customer.id}
    end)
  end
end
