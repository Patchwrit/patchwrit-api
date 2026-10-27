defmodule PatchwritApiWeb.TestMachineController do
  @moduledoc """
  Thin HTTP layer over `PatchwritApi.Fly.Client`.

  Gated by `PatchwritApiWeb.Plugs.RequireTestMachines`. No Fly logic
  lives here: parse, delegate, render.
  """

  use PatchwritApiWeb, :controller

  alias PatchwritApi.Fly.Client

  def index(conn, _params) do
    render_result(conn, Client.list_machines(), 200)
  end

  def create(conn, params) do
    render_result(conn, Client.create_machine(params), 201)
  end

  def show(conn, %{"id" => id}) do
    render_result(conn, Client.get_machine(id), 200)
  end

  def start(conn, %{"id" => id}) do
    render_result(conn, Client.start_machine(id), 200)
  end

  def stop(conn, %{"id" => id}) do
    render_result(conn, Client.stop_machine(id), 200)
  end

  def delete(conn, %{"id" => id}) do
    render_result(conn, Client.delete_machine(id), 200)
  end

  defp render_result(conn, {:ok, result}, success_status) do
    conn
    |> put_status(success_status)
    |> json(%{data: result.data, duration_ms: result.duration_ms})
  end

  defp render_result(conn, {:error, error}, _success_status) do
    status = if error.status in 400..599, do: error.status, else: 502

    conn
    |> put_status(status)
    |> json(%{error: %{status: status, message: error.message}})
  end
end
