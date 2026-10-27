defmodule PatchwritApi.Fly.ClientTest do
  use ExUnit.Case, async: false

  alias PatchwritApi.Fly.Client

  @stub PatchwritApi.FlyStub
  @machine %{
    "id" => "d5683d9d7d8e89",
    "name" => "patchwrit-test-1",
    "state" => "started",
    "region" => "iad",
    "instance_id" => "01hzy5rk4a3g6432bcwzakr0v9",
    "config" => %{"image" => "registry-1.docker.io/library/busybox:latest"}
  }

  setup do
    previous = Application.get_env(:patchwrit_api, :fly)

    Application.put_env(:patchwrit_api, :fly,
      api_token: "test-token",
      app_name: "test-app",
      base_url: "https://api.machines.dev",
      req_options: [plug: {Req.Test, @stub}]
    )

    on_exit(fn ->
      if previous,
        do: Application.put_env(:patchwrit_api, :fly, previous),
        else: Application.delete_env(:patchwrit_api, :fly)
    end)

    :ok
  end

  test "create_machine sends the allowlisted payload and normalizes the result" do
    test_pid = self()

    Req.Test.stub(@stub, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:fly_request, conn.method, conn.request_path, Jason.decode!(raw)})

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(201, Jason.encode!(@machine))
    end)

    assert {:ok, result} = Client.create_machine(%{"image" => "busybox", "region" => "iad"})
    assert result.status == 201
    assert result.duration_ms >= 0
    assert result.data.id == @machine["id"]
    assert result.data.state == "started"
    assert result.data.region == "iad"

    assert_received {:fly_request, "POST", "/v1/apps/test-app/machines", payload}
    assert payload["region"] == "iad"
    assert payload["config"]["image"] == "registry-1.docker.io/library/busybox:latest"

    assert payload["config"]["guest"] == %{
             "cpu_kind" => "shared",
             "cpus" => 1,
             "memory_mb" => 256
           }
  end

  test "create_machine rejects an unknown image without calling Fly" do
    Req.Test.stub(@stub, fn _conn -> flunk("Fly must not be called for invalid input") end)

    assert {:error, error} = Client.create_machine(%{"image" => "ubuntu"})
    assert error.status == 422
  end

  test "get, start, stop, and delete hit the machine paths" do
    test_pid = self()

    Req.Test.stub(@stub, fn conn ->
      send(test_pid, {:fly_request, conn.method, conn.request_path})

      body =
        if conn.method == "DELETE",
          do: %{"id" => @machine["id"], "deleted" => true},
          else: @machine

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(body))
    end)

    assert {:ok, %{data: %{id: id}}} = Client.get_machine(@machine["id"])
    assert id == @machine["id"]
    assert {:ok, %{status: 200}} = Client.start_machine(@machine["id"])
    assert {:ok, %{status: 200}} = Client.stop_machine(@machine["id"])
    assert {:ok, %{status: 200}} = Client.delete_machine(@machine["id"])

    base = "/v1/apps/test-app/machines/#{@machine["id"]}"
    start_path = "#{base}/start"
    stop_path = "#{base}/stop"
    assert_received {:fly_request, "GET", ^base}
    assert_received {:fly_request, "POST", ^start_path}
    assert_received {:fly_request, "POST", ^stop_path}
    assert_received {:fly_request, "DELETE", ^base}
  end

  test "invalid machine ids are rejected without calling Fly" do
    Req.Test.stub(@stub, fn _conn -> flunk("Fly must not be called for invalid input") end)

    assert {:error, %{status: 422}} = Client.get_machine("bad/id")
    assert {:error, %{status: 422}} = Client.delete_machine("")
  end

  test "upstream errors are normalized and sanitized" do
    Req.Test.stub(@stub, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(401, Jason.encode!(%{"error" => "invalid token"}))
    end)

    assert {:error, error} = Client.list_machines()
    assert error.status == 401
    assert error.message == "invalid token"
  end

  test "create_worker_machine sends the pinned image and env" do
    Application.put_env(:patchwrit_api, :fly,
      api_token: "test-token",
      app_name: "test-app",
      base_url: "https://api.machines.dev",
      worker_image: "ghcr.io/patchwrit/patchwrit-worker@sha256:abc123",
      req_options: [plug: {Req.Test, @stub}]
    )

    test_pid = self()

    Req.Test.stub(@stub, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:worker_payload, Jason.decode!(raw)})

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(201, Jason.encode!(@machine))
    end)

    assert {:ok, %{status: 201}} =
             Client.create_worker_machine(%{"env" => %{"PATCHWRIT_JOB_ID" => "job-1"}})

    assert_received {:worker_payload, payload}
    assert payload["config"]["image"] == "ghcr.io/patchwrit/patchwrit-worker@sha256:abc123"
    assert payload["config"]["env"] == %{"PATCHWRIT_JOB_ID" => "job-1"}
  end

  test "create_worker_machine refuses an unpinned worker image" do
    Application.put_env(:patchwrit_api, :fly,
      api_token: "test-token",
      app_name: "test-app",
      worker_image: "ghcr.io/patchwrit/patchwrit-worker:smoke"
    )

    Req.Test.stub(@stub, fn _conn -> flunk("Fly must not be called without a pinned image") end)
    assert {:error, %{status: 503}} = Client.create_worker_machine(%{})
  end

  test "missing configuration returns 503 without calling Fly" do
    Application.put_env(:patchwrit_api, :fly, api_token: nil, app_name: nil)

    assert {:error, error} = Client.list_machines()
    assert error.status == 503
  end
end
