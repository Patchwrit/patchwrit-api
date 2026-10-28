defmodule PatchwritApiWeb.WorkerCallbackControllerTest do
  use PatchwritApiWeb.ConnCase, async: false
  use Oban.Testing, repo: PatchwritApi.Repo

  alias PatchwritApi.Analyses

  @stub PatchwritApi.FlyStub
  @payload %{
    "schema_version" => 1,
    "job_id" => nil,
    "status" => "completed",
    "worker_version" => "0.1.0",
    "environment" => %{
      "go_version" => "go1.26.2",
      "git_version" => nil,
      "java_version" => nil,
      "maven_version" => nil
    },
    "repository" => %{
      "repository_url" => "https://github.com/spring-petclinic/spring-framework-petclinic",
      "pinned_sha" => "cf392920cdbe9cd07689f1f4b603271940bac957",
      "checked_out_sha" => "cf392920cdbe9cd07689f1f4b603271940bac957",
      "pom_files" => ["pom.xml"],
      "modules" => []
    },
    "dependencies" => [
      %{
        "group_id" => "org.apache.tomcat.embed",
        "artifact_id" => "tomcat-embed-core",
        "version" => "10.1.24",
        "scope" => "compile",
        "depth" => 2,
        "introduced_via" => [
          "com.example:app:1.0",
          "org.springframework.boot:spring-boot-starter-web:3.3.0"
        ]
      }
    ],
    "timings_ms" => %{"execution" => 12},
    "errors" => []
  }

  setup do
    previous_fly = Application.get_env(:patchwrit_api, :fly)

    Application.put_env(:patchwrit_api, :fly,
      api_token: "test-token",
      app_name: "test-app",
      base_url: "https://api.machines.dev",
      req_options: [plug: {Req.Test, @stub}]
    )

    on_exit(fn ->
      if previous_fly,
        do: Application.put_env(:patchwrit_api, :fly, previous_fly),
        else: Application.delete_env(:patchwrit_api, :fly)
    end)

    Req.Test.stub(@stub, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{"id" => "m1", "deleted" => true}))
    end)

    hash = :crypto.hash(:sha256, "job-secret") |> Base.encode16(case: :lower)

    {:ok, analysis} =
      Analyses.create_analysis(%{
        "repository_url" => "https://github.com/spring-petclinic/spring-framework-petclinic"
      })

    {:ok, analysis} = Analyses.transition(analysis, "provisioning")
    {:ok, analysis} = Analyses.transition(analysis, "running")

    {:ok, analysis} =
      Analyses.update_analysis(analysis, %{"machine_id" => "m1", "callback_token_hash" => hash})

    {:ok, analysis: analysis}
  end

  defp callback(conn, analysis, token) do
    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> post("/api/v1/worker-callbacks/#{analysis.id}", %{@payload | "job_id" => analysis.id})
  end

  test "records the result, completes the analysis, and cleans up", %{
    conn: conn,
    analysis: analysis
  } do
    conn = callback(conn, analysis, "job-secret")
    assert %{"status" => "recorded"} = json_response(conn, 200)

    updated = Analyses.get_analysis!(analysis.id)
    assert updated.status == "completed"
    assert updated.result["worker_version"] == "0.1.0"

    assert updated.result["repository"]["checked_out_sha"] ==
             "cf392920cdbe9cd07689f1f4b603271940bac957"

    assert updated.result["repository"]["pom_files"] == ["pom.xml"]

    assert [%{"artifact_id" => "tomcat-embed-core", "depth" => 2}] =
             updated.result["dependencies"]

    assert updated.machine_cleanup_status == "destroyed"

    assert_enqueued(
      worker: PatchwritApi.Workers.ScanAnalysis,
      args: %{"analysis_id" => analysis.id}
    )
  end

  test "rejects a wrong token and persists nothing", %{conn: conn, analysis: analysis} do
    conn = callback(conn, analysis, "wrong")
    assert json_response(conn, 401)
    assert Analyses.get_analysis!(analysis.id).status == "running"
  end

  test "duplicate callbacks are acknowledged without changing the record", %{
    conn: conn,
    analysis: analysis
  } do
    conn = callback(conn, analysis, "job-secret")
    assert json_response(conn, 200)

    conn = callback(build_conn(), analysis, "job-secret")
    assert %{"status" => "already_recorded"} = json_response(conn, 200)
    assert Analyses.get_analysis!(analysis.id).status == "completed"
  end
end
