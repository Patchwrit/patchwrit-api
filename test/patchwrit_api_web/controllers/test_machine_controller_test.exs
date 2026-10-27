defmodule PatchwritApiWeb.TestMachineControllerTest do
  use PatchwritApiWeb.ConnCase, async: false

  @stub PatchwritApi.FlyStub
  @machine %{
    "id" => "d5683d9d7d8e89",
    "name" => "patchwrit-test-1",
    "state" => "started",
    "region" => "iad",
    "instance_id" => "01hzy5rk4a3g6432bcwzakr0v9"
  }

  setup do
    previous_fly = Application.get_env(:patchwrit_api, :fly)
    previous_enabled = Application.get_env(:patchwrit_api, :enable_test_machine_routes)
    previous_token = Application.get_env(:patchwrit_api, :test_machines_token)

    Application.put_env(:patchwrit_api, :fly,
      api_token: "test-token",
      app_name: "test-app",
      base_url: "https://api.machines.dev",
      req_options: [plug: {Req.Test, @stub}]
    )

    Application.put_env(:patchwrit_api, :enable_test_machine_routes, true)
    Application.delete_env(:patchwrit_api, :test_machines_token)

    on_exit(fn ->
      restore(:fly, previous_fly)
      restore(:enable_test_machine_routes, previous_enabled)
      restore(:test_machines_token, previous_token)
    end)

    stub_machine()
    :ok
  end

  defp restore(key, nil), do: Application.delete_env(:patchwrit_api, key)
  defp restore(key, value), do: Application.put_env(:patchwrit_api, key, value)

  defp stub_machine do
    Req.Test.stub(@stub, fn conn ->
      body =
        cond do
          conn.method == "DELETE" -> %{"id" => @machine["id"], "deleted" => true}
          String.ends_with?(conn.request_path, "/machines") and conn.method == "GET" -> [@machine]
          true -> @machine
        end

      status =
        if conn.method == "POST" and String.ends_with?(conn.request_path, "/machines"),
          do: 201,
          else: 200

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(status, Jason.encode!(body))
    end)
  end

  test "creates, lists, shows, starts, stops, and deletes a machine", %{conn: conn} do
    conn = post(conn, "/api/v1/test-machines", %{"image" => "busybox", "region" => "iad"})

    assert %{"data" => %{"id" => id, "state" => "started"}, "duration_ms" => ms} =
             json_response(conn, 201)

    assert id == @machine["id"]
    assert ms >= 0

    conn = get(build_conn(), "/api/v1/test-machines")
    assert %{"data" => [%{"id" => ^id}]} = json_response(conn, 200)

    conn = get(build_conn(), "/api/v1/test-machines/#{id}")
    assert %{"data" => %{"id" => ^id}} = json_response(conn, 200)

    conn = post(build_conn(), "/api/v1/test-machines/#{id}/start")
    assert %{"data" => %{"id" => ^id}} = json_response(conn, 200)

    conn = post(build_conn(), "/api/v1/test-machines/#{id}/stop")
    assert %{"data" => %{"id" => ^id}} = json_response(conn, 200)

    conn = delete(build_conn(), "/api/v1/test-machines/#{id}")
    assert %{"data" => %{"id" => ^id, "deleted" => true}} = json_response(conn, 200)
  end

  test "invalid create input renders 422 without success", %{conn: conn} do
    conn = post(conn, "/api/v1/test-machines", %{"image" => "ubuntu"})
    assert %{"error" => %{"status" => 422}} = json_response(conn, 422)
  end

  test "routes are hidden when disabled and no token is configured", %{conn: conn} do
    Application.put_env(:patchwrit_api, :enable_test_machine_routes, false)

    conn = get(conn, "/api/v1/test-machines")
    assert json_response(conn, 404)
  end

  test "token-configured routes require the bearer token", %{conn: conn} do
    Application.put_env(:patchwrit_api, :enable_test_machine_routes, false)
    Application.put_env(:patchwrit_api, :test_machines_token, "secret-test-token")

    conn = get(conn, "/api/v1/test-machines")
    assert json_response(conn, 401)

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer secret-test-token")
      |> get("/api/v1/test-machines")

    assert %{"data" => [%{"id" => _}]} = json_response(conn, 200)
  end
end
