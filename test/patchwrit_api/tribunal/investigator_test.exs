defmodule PatchwritApi.Tribunal.InvestigatorTest do
  use PatchwritApi.DataCase, async: false
  use Oban.Testing, repo: PatchwritApi.Repo

  alias PatchwritApi.Analyses
  alias PatchwritApi.Findings
  alias PatchwritApi.Tribunal
  alias PatchwritApi.Tribunal.Investigator
  alias PatchwritApi.Workers.ScanAnalysis

  @stub PatchwritApi.OsvStub

  @log4j_dep %{
    "group_id" => "org.apache.logging.log4j",
    "artifact_id" => "log4j-core",
    "version" => "2.14.1",
    "scope" => "compile",
    "depth" => 1,
    "introduced_via" => ["com.example:app:1.0"]
  }
  @gson_dep %{
    "group_id" => "com.google.code.gson",
    "artifact_id" => "gson",
    "version" => "2.8.1",
    "scope" => "compile",
    "depth" => 3,
    "introduced_via" => [
      "com.example:app:1.0",
      "com.example:lib:2.0",
      "com.google.code.gson:gson:2.8.1"
    ]
  }

  setup do
    {:ok, analysis} =
      Analyses.create_analysis(%{
        "repository_url" => "https://github.com/example/app",
        "requested_ref" => "main",
        "jdk_version" => "17",
        "resolved_sha" => "0123456789abcdef0123456789abcdef01234567",
        "worker_image" => "ghcr.io/patchwrit/patchwrit-worker@sha256:abc",
        "status" => "completed",
        "result" => %{"dependencies" => [@log4j_dep, @gson_dep]}
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
          "raw" => %{
            "id" => "GHSA-jfh8-c2jp-5v3q",
            "references" => [%{"type" => "ADVISORY", "url" => "https://example.com/adv"}]
          }
        },
        %{
          "osv_id" => "GHSA-4jrv-ppp4-jm57",
          "package_name" => "com.google.code.gson:gson",
          "package_version" => "2.8.1",
          "summary" => "Denial of Service in Gson",
          "severity" => nil,
          "fixed_versions" => [],
          "aliases" => ["CVE-2022-25647"],
          "raw" => %{"id" => "GHSA-4jrv-ppp4-jm57"}
        }
      ])

    findings = Findings.list_findings_for_analysis(analysis.id)
    log4j_finding = Enum.find(findings, &(&1.osv_id == "GHSA-jfh8-c2jp-5v3q"))
    gson_finding = Enum.find(findings, &(&1.osv_id == "GHSA-4jrv-ppp4-jm57"))
    {:ok, analysis: analysis, log4j: log4j_finding, gson: gson_finding}
  end

  test "packet carries source, artifact, advisory, and provenance facts", %{
    analysis: analysis,
    log4j: finding
  } do
    packet = Investigator.build_packet(analysis, finding)

    assert packet["source"]["commit_sha"] == "0123456789abcdef0123456789abcdef01234567"
    assert packet["artifact"]["group_id"] == "org.apache.logging.log4j"
    assert packet["artifact"]["artifact_id"] == "log4j-core"
    assert packet["artifact"]["resolved_version"] == "2.14.1"
    assert packet["artifact"]["direct"] == true
    assert packet["artifact"]["introduction_paths"] == [["com.example:app:1.0"]]

    [advisory] = packet["advisories"]
    assert advisory["id"] == "GHSA-jfh8-c2jp-5v3q"
    assert advisory["aliases"] == ["CVE-2021-44228"]
    assert advisory["references"] == ["https://example.com/adv"]
    assert advisory["reachability"] == "unknown"
    assert packet["collection"]["worker_image"] =~ "sha256:abc"
  end

  test "missing-context flags name exactly what is unknown", %{
    analysis: analysis,
    log4j: log4j,
    gson: gson
  } do
    packet = Investigator.build_packet(analysis, log4j)

    # No v2 graph block on this analysis: completeness is unknown,
    # which must surface as an explicit incomplete flag.
    assert packet["missing_context"] == [
             "code_reachability_not_evaluated",
             "source_level_evidence_not_collected",
             "dependency_graph_incomplete"
           ]

    packet = Investigator.build_packet(analysis, gson)
    assert packet["artifact"]["direct"] == false
    assert "no_fixed_version_published" in packet["missing_context"]
    assert "severity_not_reported" in packet["missing_context"]
  end

  test "investigate persists one case per finding and rebuild replaces", %{
    analysis: analysis
  } do
    assert {:ok, cases} = Investigator.investigate_analysis(analysis)
    assert length(cases) == 2
    assert Enum.all?(cases, &(&1.status == "evidence_ready"))

    assert {:ok, _cases} = Investigator.investigate_analysis(analysis)
    assert Tribunal.count_cases_for_analysis(analysis.id) == 2
  end

  test "investigation records stage timings", %{analysis: analysis} do
    assert :ok =
             perform_job(PatchwritApi.Workers.InvestigateAnalysis, %{
               "analysis_id" => analysis.id
             })

    timings = Analyses.get_analysis!(analysis.id).timings
    assert is_integer(timings["investigate_ms"])
    assert timings["cases"] == 2
  end

  test "a completed scan chains into investigation", %{analysis: analysis} do
    Req.Test.set_req_test_to_shared()

    previous = Application.get_env(:patchwrit_api, :osv)

    Application.put_env(:patchwrit_api, :osv,
      base_url: "https://api.osv.dev",
      req_options: [plug: {Req.Test, @stub}]
    )

    on_exit(fn ->
      if previous,
        do: Application.put_env(:patchwrit_api, :osv, previous),
        else: Application.delete_env(:patchwrit_api, :osv)
    end)

    Req.Test.stub(@stub, fn conn -> Req.Test.json(conn, %{"results" => [%{}, %{}]}) end)

    assert :ok = perform_job(ScanAnalysis, %{"analysis_id" => analysis.id})

    assert_enqueued(
      worker: PatchwritApi.Workers.InvestigateAnalysis,
      args: %{"analysis_id" => analysis.id}
    )
  end
end
