defmodule LedgrWeb.Domains.Viaxe.TripController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.Viaxe.Trips
  alias Ledgr.Domains.Viaxe.Trips.Trip
  alias Ledgr.Domains.Viaxe.Customers

  def index(conn, params) do
    status = params["status"]
    trips = Trips.list_trips(status: status)
    render(conn, :index, trips: trips, current_status: status)
  end

  def show(conn, %{"id" => id}) do
    trip = Trips.get_trip!(id)
    render(conn, :show, trip: trip)
  end

  def new(conn, _params) do
    changeset = Trips.change_trip(%Trip{})
    customers = Customers.customer_select_options()
    render(conn, :new,
      changeset: changeset,
      customers: customers,
      action: dp(conn, "/trips")
    )
  end

  def create(conn, %{"trip" => trip_params}) do
    {passenger_ids, trip_params} = Map.pop(trip_params, "passenger_ids", [])

    case Trips.create_trip(trip_params) do
      {:ok, trip} ->
        passenger_ids
        |> List.wrap()
        |> Enum.reject(&(&1 == "" or is_nil(&1)))
        |> Enum.each(&Trips.add_passenger(trip.id, &1))

        conn
        |> put_flash(:info, "Trip created successfully.")
        |> redirect(to: dp(conn, "/trips/#{trip.id}"))

      {:error, %Ecto.Changeset{} = changeset} ->
        customers = Customers.customer_select_options()
        render(conn, :new,
          changeset: changeset,
          customers: customers,
          action: dp(conn, "/trips")
        )
    end
  end

  def edit(conn, %{"id" => id}) do
    trip = Trips.get_trip!(id)
    changeset = Trips.change_trip(trip)
    customers = Customers.customer_select_options()
    current_passenger_ids = Enum.map(trip.passengers, & &1.id)

    render(conn, :edit,
      trip: trip,
      changeset: changeset,
      customers: customers,
      current_passenger_ids: current_passenger_ids,
      action: dp(conn, "/trips/#{id}")
    )
  end

  def update(conn, %{"id" => id, "trip" => trip_params}) do
    trip = Trips.get_trip!(id)
    {new_passenger_ids, trip_params} = Map.pop(trip_params, "passenger_ids", [])

    case Trips.update_trip(trip, trip_params) do
      {:ok, trip} ->
        new_passenger_ids =
          new_passenger_ids
          |> List.wrap()
          |> Enum.reject(&(&1 == "" or is_nil(&1)))
          |> Enum.map(&String.to_integer(to_string(&1)))

        current_ids = Enum.map(trip.passengers, & &1.id)

        (current_ids -- new_passenger_ids)
        |> Enum.each(&Trips.remove_passenger(trip.id, &1))

        (new_passenger_ids -- current_ids)
        |> Enum.each(&Trips.add_passenger(trip.id, &1))

        conn
        |> put_flash(:info, "Trip updated successfully.")
        |> redirect(to: dp(conn, "/trips/#{trip.id}"))

      {:error, %Ecto.Changeset{} = changeset} ->
        customers = Customers.customer_select_options()
        current_passenger_ids = Enum.map(trip.passengers, & &1.id)

        render(conn, :edit,
          trip: trip,
          changeset: changeset,
          customers: customers,
          current_passenger_ids: current_passenger_ids,
          action: dp(conn, "/trips/#{id}")
        )
    end
  end

  def delete(conn, %{"id" => id}) do
    trip = Trips.get_trip!(id)
    {:ok, _} = Trips.delete_trip(trip)

    conn
    |> put_flash(:info, "Trip deleted successfully.")
    |> redirect(to: dp(conn, "/trips"))
  end
end

defmodule LedgrWeb.Domains.Viaxe.TripHTML do
  use LedgrWeb, :html

  embed_templates "trip_html/*"

  def status_class("planning"), do: ""
  def status_class("confirmed"), do: "status-paid"
  def status_class("active"), do: "status-partial"
  def status_class("completed"), do: "status-paid"
  def status_class("cancelled"), do: "status-unpaid"
  def status_class(_), do: ""
end
