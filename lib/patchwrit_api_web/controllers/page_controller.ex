defmodule PatchwritApiWeb.PageController do
  use PatchwritApiWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
