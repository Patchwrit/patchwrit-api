defmodule PatchwritApiWeb.RepositoryLiveTest do
  use PatchwritApiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias PatchwritApi.Analyses
  alias PatchwritApi.Findings
  alias PatchwritApi.Repositories
  alias PatchwritApi.Tribunal
  alias PatchwritApi.Tribunal.Investigator

  @stub PatchwritApi.RepoPageGitHubStub
  @repo "https://github.com/spring-petclinic/spring-framework-petclinic"

  setup do
    Req.Test.set_req_test_to_shared()
    previous = Application.get_env(:patchwrit_api, :github)

    Application.put_env(:patchwrit_api, :github,
      base_url: "https://api.github.com",
      req_options: [plug: {Req.Test, @stub}]
    )

    on_exit(fn ->
      if previous,
        do: Application.put_env(:patchwrit_api, :github, previous),
        else: Application.delete_env(:patchwrit_api, :github)
    end)

    Req.Test.stub(@stub, fn conn ->
      case conn.request_path do
        "/repos/spring-petclinic/spring-framework-petclinic" ->
          Req.Test.json(conn, %{"default_branch" => "main"})

        "/repos/spring-petclinic/spring-framework-petclinic/branches" ->
          Req.Test.json(conn, [
            %{"name" => "main", "commit" => %{"sha" => "aaa"}},
            %{"name" => "javaconfig", "commit" => %{"sha" => "bbb"}}
          ])

        _ ->
          conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"message" => "Not Found"})
      end
    end)

    :ok
  end

  defp seed_posture do
    {:ok, repository} =
      Repositories.create_repository(%{
        "repository_url" => "https://github.com/example/app",
        "default_ref" => "main",
        "java_version" => "21"
      })

    {:ok, analysis} =
      Analyses.create_analysis(%{
        "repository_id" => repository.id,
        "repository_url" => "https://github.com/example/app",
        "requested_ref" => "main",
        "jdk_version" => "21",
        "resolved_sha" => "0123456789abcdef0123456789abcdef01234567",
        "worker_image" => "ghcr.io/patchwrit/patchwrit-worker@sha256:abc",
        "status" => "completed",
        "result" => %{
          "dependencies" => [
            %{
              "group_id" => "org.apache.logging.log4j",
              "artifact_id" => "log4j-core",
              "version" => "2.14.1",
              "scope" => "compile",
              "depth" => 1,
              "introduced_via" => ["com.example:app:1.0"]
            }
          ]
        }
      })

    {:ok, analysis} =
      Findings.record_scan(analysis, [
        %{
          "osv_id" => "GHSA-jfh8-c2jp-5v3q",
          "package_name" => "org.apache.logging.log4j:log4j-core",
          "package_version" => "2.14.1",
          "summary" => "Apache Log4j2 vulnerable to RCE via JNDI",
          "severity" => "CVSS:3.1/AV:N",
          "fixed_versions" => ["2.17.0"],
          "aliases" => ["CVE-2021-44228"],
          "raw" => %{"id" => "GHSA-jfh8-c2jp-5v3q"}
        }
      ])

    {:ok, [case_record]} = Investigator.investigate_analysis(analysis)

    {:ok, _verdict} =
      Tribunal.create_verdict(%{
        "tribunal_case_id" => case_record.id,
        "model" => "muse-wonder-1.0",
        "prompt_version" => "judge_v1",
        "snapshot_hash" => case_record.snapshot_hash,
        "status" => "completed",
        "presence" => "confirmed",
        "application_relevance" => "high",
        "exploitability" => "unknown",
        "priority" => "high",
        "judge_recommendation" => "investigate_usage",
        "recommendation" => "needs_human_review",
        "policy_capped" => true,
        "policy_notes" => ["dependency graph incomplete or unknown"],
        "supporting_evidence_ids" => ["artifact"],
        "rationale" => "Presence is proven; exploitability is not established."
      })

    repository
  end

  test "table shows latest posture with worst verdict and attention count", %{conn: conn} do
    repository = seed_posture()
    {:ok, _view, html} = live(conn, "/repositories")

    assert html =~ "Tracked repositories"
    assert html =~ "Worst verdict"
    assert html =~ "https://github.com/example/app"
    assert html =~ "Needs human review"
    assert html =~ "Graph completeness unknown"
    assert html =~ "pw-attention-count"
    assert html =~ "run-repository-#{repository.id}"
    # Sidebar marks Repositories active and the table is a real table.
    assert html =~ "pw-table"
    assert html =~ "Repositories"
  end

  test "empty library shows the empty state and tracking form", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/repositories")
    assert html =~ "No tracked repositories yet"
    assert html =~ "Track a repository"
  end

  test "tracking a repository from this page adds a table row", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/repositories")

    view
    |> form("#repository-form", repository: %{repository_url: @repo})
    |> render_submit()

    html = render(view)
    assert html =~ @repo
    assert Repositories.list_repositories() |> length() == 1
  end
end
