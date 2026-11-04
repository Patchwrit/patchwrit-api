defmodule PatchwritApiWeb.HistoryLiveTest do
  use PatchwritApiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias PatchwritApi.Analyses
  alias PatchwritApi.Findings
  alias PatchwritApi.Tribunal
  alias PatchwritApi.Tribunal.Investigator

  test "history lists runs with findings and tribunal progress", %{conn: conn} do
    {:ok, analysis} =
      Analyses.create_analysis(%{
        "repository_url" => "https://github.com/example/app",
        "requested_ref" => "main",
        "jdk_version" => "17",
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

    {:ok, _view, html} = live(conn, "/runs")
    assert html =~ "All analyses"
    assert html =~ "example/app"
    assert html =~ "1/1 judged"
    assert html =~ "Needs human review"
    assert html =~ "Tribunal status"
  end

  test "empty history is honest", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/runs")
    assert html =~ "No analyses yet"
  end
end
