defmodule LedgrWeb.PageController do
  use LedgrWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
