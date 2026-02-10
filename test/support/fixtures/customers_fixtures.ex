defmodule Ledgr.CustomersFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Ledgr.Customers` context.
  """

  @doc """
  Generate a customer.
  """
  def customer_fixture(attrs \\ %{}) do
    {:ok, customer} =
      attrs
      |> Enum.into(%{
        email: "some@email.com",
        name: "some name",
        phone: "some phone"
      })
      |> Ledgr.Customers.create_customer()

    customer
  end
end
