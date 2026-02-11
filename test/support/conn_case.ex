defmodule LedgrWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use LedgrWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint LedgrWeb.Endpoint

      use LedgrWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import LedgrWeb.ConnCase
    end
  end

  setup tags do
    Ledgr.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Creates a test user and logs them in by setting the domain-scoped session key.

  Returns the conn with the session initialized. The domain slug defaults to
  "mr-munch-me" since tests run against the MrMunchMe repo by default.

  ## Examples

      setup %{conn: conn} do
        {:ok, conn: log_in_user(conn)}
      end

  """
  def log_in_user(conn, opts \\ []) do
    slug = Keyword.get(opts, :slug, "mr-munch-me")
    email = Keyword.get(opts, :email, "test@example.com")
    password = Keyword.get(opts, :password, "password123!")

    {:ok, user} =
      Ledgr.Core.Accounts.create_user(%{email: email, password: password})

    conn
    |> Phoenix.ConnTest.init_test_session(%{"user_id:#{slug}" => user.id})
  end
end
