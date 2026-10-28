defmodule PatchwritApi.DispatchTest do
  use PatchwritApi.DataCase, async: false

  alias PatchwritApi.Analyses
  alias PatchwritApi.Dispatch

  @stub PatchwritApi.FlyStub

  setup do
    previous_fly = Application.get_env(:patchwrit_api, :fly)
    previous_base = Application.get_env(:patchwrit_api, :callback_base_url)
    previous_resolver = Application.get_env(:patchwrit_api, :sha_resolver)

    Application.put_env(:patchwrit_api, :callback_base_url, "https://callback.example")

    Application.put_env(:patchwrit_api, :sha_resolver, fn _url, _ref ->
      {:ok, "0123456789abcdef0123456789abcdef01234567"}
    end)

    Application.put_env(:patchwrit_api, :fly,
      api_token: "test-token",
      app_name: "test-app",
      base_url: "https://api.machines.dev",
      worker_images: %{"jdk17" => "ghcr.io/patchwrit/patchwrit-worker@sha256:jdk17"},
      req_options: [plug: {Req.Test, @stub}]
    )

    on_exit(fn ->
      restore(:fly, previous_fly)
      restore(:callback_base_url, previous_base)
      restore(:sha_resolver, previous_resolver)
    end)

    :ok
  end

  defp restore(key, nil), do: Application.delete_env(:patchwrit_api, key)
  defp restore(key, value), do: Application.put_env(:patchwrit_api, key, value)

  defp json(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end

  test "fails fast when the worker Machine stops before any callback" do
    Req.Test.stub(@stub, fn conn ->
      case {conn.method, conn.request_path} do
        {"POST", "/v1/apps/test-app/machines"} ->
          json(conn, 201, %{"id" => "m1", "state" => "started"})

        {"GET", "/v1/apps/test-app/machines/m1"} ->
          json(conn, 200, %{"id" => "m1", "state" => "stopped"})

        {"DELETE", "/v1/apps/test-app/machines/m1"} ->
          json(conn, 200, %{"deleted" => true})
      end
    end)

    {:ok, analysis} =
      Analyses.create_analysis(%{
        "repository_url" => "https://github.com/example/app",
        "jdk_version" => "17"
      })

    assert :ok = Dispatch.run(analysis.id)

    finished = Analyses.get_analysis!(analysis.id)
    assert finished.status == "failed"
    assert finished.error_message =~ "stopped before callback"
    assert finished.machine_cleanup_status == "destroyed"
    assert is_integer(finished.timings["dispatch_ms"])
  end
end
