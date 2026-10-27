defmodule PatchwritApiWeb.Plugs.RequireTestMachines do
  @moduledoc """
  Gate for the test-machine routes.

  These routes can create real Fly Machines, so they are never public:

  - If `TEST_MACHINES_TOKEN` is configured (app config
    `:test_machines_token`), every request must present it as a Bearer
    token. This takes precedence in every environment.
  - Otherwise the routes are available only when
    `:enable_test_machine_routes` is true (set in dev and test).
  - In all other cases the routes answer 404, as if they did not exist.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  def init(opts), do: opts

  def call(conn, _opts) do
    token = Application.get_env(:patchwrit_api, :test_machines_token)

    cond do
      is_binary(token) and token != "" -> require_bearer(conn, token)
      Application.get_env(:patchwrit_api, :enable_test_machine_routes, false) -> conn
      true -> deny(conn, 404, "not found")
    end
  end

  defp require_bearer(conn, token) do
    expected = "Bearer #{token}"

    authorized? =
      case get_req_header(conn, "authorization") do
        [^expected] -> true
        [presented] -> Plug.Crypto.secure_compare(presented, expected)
        _ -> false
      end

    if authorized?, do: conn, else: deny(conn, 401, "unauthorized")
  end

  defp deny(conn, status, message) do
    conn
    |> put_status(status)
    |> json(%{error: %{status: status, message: message}})
    |> halt()
  end
end
