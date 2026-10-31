defmodule PatchwritApiWeb.RunPageTribunalTest do
  use PatchwritApiWeb.ConnCase, async: false
  use Oban.Testing, repo: PatchwritApi.Repo

  import Phoenix.LiveViewTest

  alias PatchwritApi.Analyses
  alias PatchwritApi.Findings
  alias PatchwritApi.Tribunal
  alias PatchwritApi.Tribunal.Investigator
  alias PatchwritApi.Workers.RunTribunalCase

  defp seed_analysis do
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
    [finding] = Findings.list_findings_for_analysis(analysis.id)
    {analysis, finding, case_record}
  end

  defp judge_case(case_record) do
    for role <- ["prosecutor", "defender"] do
      {:ok, _} =
        Tribunal.create_opinion(%{
          "tribunal_case_id" => case_record.id,
          "role" => role,
          "model" => "muse-spark-1.3",
          "prompt_version" => "advocates_v1",
          "snapshot_hash" => case_record.snapshot_hash,
          "status" => "completed",
          "summary" => "#{role} argued from the dossier.",
          "arguments" => [
            %{"text" => "The artifact is present", "evidence_ids" => ["artifact"]}
          ],
          "uncertainties" => ["reachability unknown"],
          "citations" => ["artifact"],
          "usage" => %{"total_tokens" => 100}
        })
    end

    {:ok, _} =
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
        "rationale" => "Presence is proven; exploitability is not established.",
        "usage" => %{"total_tokens" => 250}
      })
  end

  test "judged finding expands into verdict, arguments, dossier, and spend", %{conn: conn} do
    {analysis, finding, case_record} = seed_analysis()
    judge_case(case_record)

    {:ok, view, html} = live(conn, "/analyses/#{analysis.id}")
    assert html =~ "Needs human review"

    html =
      view
      |> element("button[phx-click='toggle_finding'][phx-value-id='#{finding.id}']")
      |> render_click()

    assert html =~ "POLICY OVERRIDE — HUMAN REVIEW REQUIRED"
    assert html =~ "Judge proposed: Investigate usage"
    assert html =~ "Presence is proven; exploitability is not established."
    assert html =~ "prosecutor argued from the dossier."
    assert html =~ "artifact"
    assert html =~ "Evidence dossier"
    assert html =~ "450 tokens measured"
  end

  test "not-judged finding expands to the reason and a Run tribunal action", %{conn: conn} do
    {analysis, finding, case_record} = seed_analysis()

    {:ok, view, _html} = live(conn, "/analyses/#{analysis.id}")

    html =
      view
      |> element("button[phx-click='toggle_finding'][phx-value-id='#{finding.id}']")
      |> render_click()

    assert html =~ "has not been argued yet"
    assert html =~ "Selected by triage"

    view
    |> element("button[phx-click='run_tribunal'][phx-value-id='#{case_record.id}']")
    |> render_click()

    assert_enqueued(worker: RunTribunalCase, args: %{"case_id" => case_record.id})
    assert render(view) =~ "Queued"
  end
end
