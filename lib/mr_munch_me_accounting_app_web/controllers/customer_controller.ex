defmodule MrMunchMeAccountingAppWeb.CustomerController do
  use MrMunchMeAccountingAppWeb, :controller

  alias MrMunchMeAccountingApp.Customers
  alias MrMunchMeAccountingApp.Customers.Customer

  def index(conn, _params) do
    customers = Customers.list_customers()
    render(conn, :index, customers: customers)
  end

  def show(conn, %{"id" => id}) do
    customer = Customers.get_customer!(id)
    render(conn, :show, customer: customer)
  end

  def api_show(conn, %{"id" => id}) do
    customer = Customers.get_customer!(id)

    json(conn, %{
      id: customer.id,
      name: customer.name,
      phone: customer.phone,
      email: customer.email,
      delivery_address: customer.delivery_address
    })
  end

  def new(conn, _params) do
    changeset = Customers.change_customer(%Customer{})
    render(conn, :new, changeset: changeset, action: ~p"/customers")
  end

  def create(conn, %{"customer" => customer_params}) do
    case Customers.create_customer(customer_params) do
      {:ok, customer} ->
        conn
        |> put_flash(:info, "Customer created successfully.")
        |> redirect(to: ~p"/customers/#{customer}")

      {:error, %Ecto.Changeset{} = changeset} ->
        changeset = Map.put(changeset, :action, :insert)
        render(conn, :new, changeset: changeset, action: ~p"/customers")
    end
  end

  def edit(conn, %{"id" => id}) do
    customer = Customers.get_customer!(id)
    changeset = Customers.change_customer(customer)
    render(conn, :edit, customer: customer, changeset: changeset, action: ~p"/customers/#{customer}")
  end

  def update(conn, %{"id" => id, "customer" => customer_params}) do
    customer = Customers.get_customer!(id)

    case Customers.update_customer(customer, customer_params) do
      {:ok, customer} ->
        conn
        |> put_flash(:info, "Customer updated successfully.")
        |> redirect(to: ~p"/customers/#{customer}")

      {:error, %Ecto.Changeset{} = changeset} ->
        changeset = Map.put(changeset, :action, :update)
        render(conn, :edit, customer: customer, changeset: changeset, action: ~p"/customers/#{customer}")
    end
  end

  def delete(conn, %{"id" => id}) do
    customer = Customers.get_customer!(id)
    {:ok, _customer} = Customers.delete_customer(customer)

    conn
    |> put_flash(:info, "Customer deleted successfully.")
    |> redirect(to: ~p"/customers")
  end
end

defmodule MrMunchMeAccountingAppWeb.CustomerHTML do
  use MrMunchMeAccountingAppWeb, :html
  import MrMunchMeAccountingAppWeb.CoreComponents

  embed_templates "customer_html/*"
end
