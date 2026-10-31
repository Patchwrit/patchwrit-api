defmodule PatchwritApiWeb.AuditTabTest do
  use PatchwritApiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias PatchwritApi.Analyses
  alias PatchwritApi.Findings
  alias PatchwritApi.Tribunal
  alias PatchwritApi.Tribunal.Investigator

  defp seed_judged_case do
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

    {:ok, _} =
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

    {:ok, opinion} =
      Tribunal.create_opinion(%{
        "tribunal_case_id" => case_record.id,
        "role" => "prosecutor",
        "model" => "muse-spark-1.3",
        "prompt_version" => "advocates_v2",
        "snapshot_hash" => case_record.snapshot_hash,
        "status" => "completed",
        "summary" => "log4j-core 2.14.1 is present and direct, with a known RCE.",
        "arguments" => [%{"text" => "Present and direct", "evidence_ids" => ["artifact"]}],
        "uncertainties" => ["code reachability not evaluated"],
        "citations" => ["artifact"],
        "usage" => %{
          "total_tokens" => 4_000,
          "prompt_tokens" => 1_500,
          "completion_tokens" => 2_500,
          "prompt_tokens_details" => %{"cached_tokens" => 500},
          "completion_tokens_details" => %{"reasoning_tokens" => 1_800}
        }
      })

    {:ok, verdict} =
      Tribunal.create_verdict(%{
        "tribunal_case_id" => case_record.id,
        "model" => "muse-wonder-1.0",
        "prompt_version" => "judge_v2",
        "policy_version" => "policy_v1",
        "snapshot_hash" => case_record.snapshot_hash,
        "status" => "completed",
        "presence" => "confirmed",
        "application_relevance" => "high",
        "exploitability" => "unknown",
        "priority" => "high",
        "judge_recommendation" => "remediate_now",
        "recommendation" => "needs_human_review",
        "policy_capped" => true,
        "policy_notes" => ["dependency graph incomplete or unknown"],
        "supporting_evidence_ids" => ["artifact"],
        "rationale" => "Presence is proven; exploitability is not established.",
        "usage" => %{"total_tokens" => 6_000}
      })

    record = fn event, actor, metadata ->
      Tribunal.record_audit_event(case_record, event, actor, metadata)
    end

    record.("tribunal_queued", "operator", %{
      "source" => "manual",
      "advocate_model" => "muse-spark-1.3",
      "judge_model" => "muse-wonder-1.0"
    })

    record.("opinion_completed", "prosecutor", %{
      "opinion_id" => opinion.id,
      "model" => "muse-spark-1.3",
      "total_tokens" => 4_000,
      "prompt_tokens" => 1_500,
      "cached_tokens" => 500
    })

    record.("verdict_completed", "judge", %{
      "verdict_id" => verdict.id,
      "total_tokens" => 6_000,
      "policy_version" => "policy_v1"
    })

    record.("policy_applied", "policy_gate", %{
      "verdict_id" => verdict.id,
      "policy_version" => "policy_v1",
      "judge_recommendation" => "remediate_now",
      "recommendation" => "needs_human_review",
      "policy_notes" => ["dependency graph incomplete or unknown"]
    })

    {analysis, case_record}
  end

  test "audit tab tells the decision story, not just event names", %{conn: conn} do
    {analysis, _case_record} = seed_judged_case()

    {:ok, _view, html} = live(conn, "/analyses/#{analysis.id}/audit")

    # Summary strip
    assert html =~ "Decision stream"
    assert html =~ "Cases judged"
    assert html =~ "10,000"
    assert html =~ "Policy caps"

    # Entries are plain-language decisions with the evidence behind them.
    assert html =~ "Evidence collected"
    assert html =~ "Queued for tribunal"
    assert html =~ "Queued manually."
    assert html =~ "Prosecutor argued the case"
    assert html =~ "log4j-core 2.14.1 is present and direct"
    assert html =~ "1 evidence citation(s)"
    assert html =~ "Verdict: Needs human review"
    assert html =~ "Judge proposed Remediate now"
    assert html =~ "Exploitability unknown"
    assert html =~ "Policy capped the verdict"
    assert html =~ "dependency graph incomplete or unknown"
    assert html =~ "not a safety finding"

    # Each entry links back to its finding's case page.
    assert html =~ "org.apache.logging.log4j:log4j-core:2.14.1"
    assert html =~ "/findings/"
  end

  test "run tabs include Audit alongside the other sections", %{conn: conn} do
    {analysis, _case_record} = seed_judged_case()

    {:ok, _view, html} = live(conn, "/analyses/#{analysis.id}")
    assert html =~ "/analyses/#{analysis.id}/audit"
    assert html =~ "Audit"
  end

  test "audit tab is honestly empty before any tribunal activity", %{conn: conn} do
    {:ok, analysis} =
      Analyses.create_analysis(%{
        "repository_url" => "https://github.com/example/empty",
        "requested_ref" => "main",
        "jdk_version" => "17",
        "status" => "completed"
      })

    {:ok, _view, html} = live(conn, "/analyses/#{analysis.id}/audit")
    assert html =~ "No audit events recorded for this run yet"
  end
end
