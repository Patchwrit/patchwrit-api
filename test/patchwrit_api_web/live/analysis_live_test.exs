defmodule PatchwritApiWeb.AnalysisLiveTest do
  use PatchwritApiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias PatchwritApi.Analyses
  alias PatchwritApi.Repositories

  @stub PatchwritApi.GitHubStub
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

  test "renders the tracked repository form and empty states", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/analyses")
    assert html =~ "Track a repository"
    assert html =~ "No tracked repositories yet"
    assert html =~ "No analyses yet"
    assert html =~ "/patchwrit.css"
    assert html =~ "pw-shell"
  end

  test "entering a repository URL fetches branches on the spot", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/analyses")

    view
    |> form("#repository-form", repository: %{repository_url: @repo})
    |> render_change()

    html = render(view)
    assert html =~ "javaconfig"
    assert html =~ "Branches loaded from GitHub"
  end

  test "tracking a repository and running it snapshots its configuration", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/analyses")

    view
    |> form("#repository-form",
      repository: %{repository_url: @repo, default_ref: "javaconfig", java_version: "17"}
    )
    |> render_submit()

    html = render(view)
    assert html =~ @repo
    assert html =~ "JDK 17"
    assert html =~ "javaconfig"

    assert [%{repository_url: @repo, default_ref: "javaconfig", java_version: "17"}] =
             Repositories.list_repositories()

    repository = hd(Repositories.list_repositories())

    view
    |> element("#run-repository-#{repository.id}")
    |> render_click()

    assert render(view) =~ "queued"

    assert [%{repository_id: repository_id, jdk_version: "17", requested_ref: "javaconfig"}] =
             Analyses.list_analyses()

    assert repository_id == repository.id
  end

  test "tracking an invalid repository shows an error and persists nothing", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/analyses")

    view
    |> form("#repository-form", repository: %{repository_url: "https://example.com/a/b"})
    |> render_submit()

    assert render(view) =~ "must be a public GitHub repository URL"
    assert Repositories.list_repositories() == []
  end

  test "detail page shows findings with severity, fix, and introduction path", %{conn: conn} do
    {:ok, analysis} =
      Analyses.create_analysis(%{
        "repository_url" => @repo,
        "status" => "completed",
        "osv_scanned_at" => DateTime.utc_now() |> DateTime.truncate(:second),
        "result" => %{
          "dependencies" => [
            %{
              "group_id" => "org.apache.logging.log4j",
              "artifact_id" => "log4j-core",
              "version" => "2.14.1",
              "introduced_via" => ["com.example:app:1.0"]
            }
          ]
        }
      })

    {:ok, _updated} =
      PatchwritApi.Findings.record_scan(analysis, [
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

    {:ok, _view, html} = live(conn, "/analyses/#{analysis.id}")
    assert html =~ "Findings (1)"
    assert html =~ "org.apache.logging.log4j:log4j-core:2.14.1"
    assert html =~ "CVE-2021-44228"
    assert html =~ "fixed in 2.17.0"
    assert html =~ "via com.example:app:1.0"
  end

  test "detail page distinguishes scanned-clean from not-yet-scanned", %{conn: conn} do
    {:ok, scanned} =
      Analyses.create_analysis(%{
        "repository_url" => @repo,
        "status" => "completed",
        "osv_scanned_at" => DateTime.utc_now() |> DateTime.truncate(:second)
      })

    {:ok, _view, html} = live(conn, "/analyses/#{scanned.id}")
    assert html =~ "Findings (0)"
    assert html =~ "No known vulnerabilities"

    {:ok, unscanned} =
      Analyses.create_analysis(%{"repository_url" => @repo, "status" => "completed"})

    {:ok, _view, html} = live(conn, "/analyses/#{unscanned.id}")
    assert html =~ "Not yet scanned"
    refute html =~ "No known vulnerabilities"
  end

  test "detail page shows stage timings and per-module instrumentation", %{conn: conn} do
    {:ok, analysis} =
      Analyses.create_analysis(%{
        "repository_url" => @repo,
        "status" => "completed",
        "timings" => %{"dispatch_ms" => 1200, "scan_ms" => 340},
        "result" => %{
          "graph" => %{
            "complete" => true,
            "modules_total" => 1,
            "modules_resolved" => 1,
            "downloaded_artifacts" => 643,
            "downloaded_bytes" => 17_965_539,
            "modules" => [
              %{
                "module" => "com.example:app",
                "pom_path" => "pom.xml",
                "status" => "resolved",
                "duration_ms" => 17691,
                "dependencies" => 42
              }
            ]
          }
        }
      })

    {:ok, _view, html} = live(conn, "/analyses/#{analysis.id}")
    assert html =~ "Stage timings"
    assert html =~ "dispatch_ms"
    assert html =~ "643 files"
    assert html =~ "com.example:app"
    assert html =~ "17691 ms"
  end

  test "detail page shows JDK, status, and cleanup state", %{conn: conn} do
    {:ok, repository} =
      Repositories.create_repository(%{
        "repository_url" => @repo,
        "default_ref" => "main",
        "java_version" => "21"
      })

    {:ok, analysis} = Analyses.create_analysis_for_repository(repository)

    {:ok, _view, html} = live(conn, "/analyses/#{analysis.id}")
    assert html =~ @repo
    assert html =~ "JDK 21"
    assert html =~ "queued"
    assert html =~ "pending"
    assert html =~ analysis.id
  end
end
