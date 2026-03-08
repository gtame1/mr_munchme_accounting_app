defmodule LedgrWeb.Storefront.CartControllerTest do
  use LedgrWeb.ConnCase, async: true

  import Ledgr.Domains.MrMunchMe.OrdersFixtures

  # ---------------------------------------------------------------------------
  # GET /mr-munch-me/cart
  # ---------------------------------------------------------------------------

  describe "GET /mr-munch-me/cart (index)" do
    test "renders empty cart when session has no cart", %{conn: conn} do
      conn = get(conn, "/mr-munch-me/cart")
      assert html_response(conn, 200)
    end

    test "renders cart with items from session", %{conn: conn} do
      product = product_fixture(%{name: "Carrot Cake"})
      variant = variant_fixture(%{product: product, name: "Chico", price_cents: 12000})

      conn =
        conn
        |> init_test_session(%{cart: %{to_string(variant.id) => 2}})
        |> get("/mr-munch-me/cart")

      body = html_response(conn, 200)
      assert body =~ "Carrot Cake"
      assert body =~ "Chico"
    end

    test "ignores stale variant ids in the cart", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{cart: %{"999999" => 1}})
        |> get("/mr-munch-me/cart")

      # Should still return 200 — stale variant silently dropped
      assert html_response(conn, 200)
    end
  end

  # ---------------------------------------------------------------------------
  # POST /mr-munch-me/cart/add
  # ---------------------------------------------------------------------------

  describe "POST /mr-munch-me/cart/add (add)" do
    test "adds variant to the cart and redirects to menu", %{conn: conn} do
      product = product_fixture(%{name: "Brownie Box"})
      variant = variant_fixture(%{product: product, price_cents: 8000, active: true})

      conn =
        post(conn, "/mr-munch-me/cart/add", %{
          "variant_id" => variant.id,
          "quantity" => "1"
        })

      assert redirected_to(conn) == "/mr-munch-me/menu"
      assert get_session(conn, :cart)[to_string(variant.id)] == 1
    end

    test "accumulates quantity when the same variant is added again", %{conn: conn} do
      product = product_fixture()
      variant = variant_fixture(%{product: product, active: true})

      # First add
      conn =
        conn
        |> init_test_session(%{cart: %{to_string(variant.id) => 2}})
        |> post("/mr-munch-me/cart/add", %{
          "variant_id" => variant.id,
          "quantity" => "3"
        })

      assert get_session(conn, :cart)[to_string(variant.id)] == 5
    end

    test "adds multiple different variants to the cart", %{conn: conn} do
      product = product_fixture()
      variant_a = variant_fixture(%{product: product, active: true})
      variant_b = variant_fixture(%{product: product, name: "Grande", active: true})

      conn1 =
        post(conn, "/mr-munch-me/cart/add", %{
          "variant_id" => variant_a.id,
          "quantity" => "1"
        })

      conn2 =
        conn1
        |> recycle()
        |> post("/mr-munch-me/cart/add", %{
          "variant_id" => variant_b.id,
          "quantity" => "2"
        })

      cart = get_session(conn2, :cart)
      assert cart[to_string(variant_a.id)] == 1
      assert cart[to_string(variant_b.id)] == 2
    end

    test "minimum quantity is 1 even when 0 is submitted", %{conn: conn} do
      product = product_fixture()
      variant = variant_fixture(%{product: product, active: true})

      conn =
        post(conn, "/mr-munch-me/cart/add", %{
          "variant_id" => variant.id,
          "quantity" => "0"
        })

      assert get_session(conn, :cart)[to_string(variant.id)] == 1
    end

    test "shows flash confirmation after add", %{conn: conn} do
      product = product_fixture(%{name: "Cookie Box"})
      variant = variant_fixture(%{product: product, name: "Mediano", active: true})

      conn =
        post(conn, "/mr-munch-me/cart/add", %{
          "variant_id" => variant.id,
          "quantity" => "1"
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "agregado al carrito"
    end
  end

  # ---------------------------------------------------------------------------
  # PUT /mr-munch-me/cart/update
  # ---------------------------------------------------------------------------

  describe "PUT /mr-munch-me/cart/update (update)" do
    test "updates the quantity for an existing cart item", %{conn: conn} do
      product = product_fixture()
      variant = variant_fixture(%{product: product, active: true})

      conn =
        conn
        |> init_test_session(%{cart: %{to_string(variant.id) => 1}})
        |> put("/mr-munch-me/cart/update", %{
          "variant_id" => variant.id,
          "quantity" => "5"
        })

      assert redirected_to(conn) == "/mr-munch-me/cart"
      assert get_session(conn, :cart)[to_string(variant.id)] == 5
    end

    test "removes item from cart when quantity is set to 0", %{conn: conn} do
      product = product_fixture()
      variant = variant_fixture(%{product: product, active: true})

      conn =
        conn
        |> init_test_session(%{cart: %{to_string(variant.id) => 3}})
        |> put("/mr-munch-me/cart/update", %{
          "variant_id" => variant.id,
          "quantity" => "0"
        })

      refute Map.has_key?(get_session(conn, :cart), to_string(variant.id))
    end

    test "removes item from cart when quantity is negative", %{conn: conn} do
      product = product_fixture()
      variant = variant_fixture(%{product: product, active: true})

      conn =
        conn
        |> init_test_session(%{cart: %{to_string(variant.id) => 3}})
        |> put("/mr-munch-me/cart/update", %{
          "variant_id" => variant.id,
          "quantity" => "-1"
        })

      refute Map.has_key?(get_session(conn, :cart), to_string(variant.id))
    end
  end

  # ---------------------------------------------------------------------------
  # POST /mr-munch-me/cart/remove
  # ---------------------------------------------------------------------------

  describe "POST /mr-munch-me/cart/remove (remove)" do
    test "removes the specified item from the cart", %{conn: conn} do
      product = product_fixture()
      variant = variant_fixture(%{product: product, active: true})

      conn =
        conn
        |> init_test_session(%{cart: %{to_string(variant.id) => 2}})
        |> post("/mr-munch-me/cart/remove", %{"variant_id" => variant.id})

      assert redirected_to(conn) == "/mr-munch-me/cart"
      refute Map.has_key?(get_session(conn, :cart), to_string(variant.id))
    end

    test "shows flash after removal", %{conn: conn} do
      product = product_fixture()
      variant = variant_fixture(%{product: product, active: true})

      conn =
        conn
        |> init_test_session(%{cart: %{to_string(variant.id) => 1}})
        |> post("/mr-munch-me/cart/remove", %{"variant_id" => variant.id})

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "eliminado del carrito"
    end

    test "removing a variant not in the cart is a no-op", %{conn: conn} do
      product = product_fixture()
      variant_a = variant_fixture(%{product: product, active: true})
      variant_b = variant_fixture(%{product: product, name: "Grande", active: true})

      conn =
        conn
        |> init_test_session(%{cart: %{to_string(variant_a.id) => 1}})
        |> post("/mr-munch-me/cart/remove", %{"variant_id" => variant_b.id})

      # variant_a should still be in the cart
      assert get_session(conn, :cart)[to_string(variant_a.id)] == 1
    end
  end
end
