defmodule PatchwritApi.Workers.RunTribunalCaseTest do
  use PatchwritApi.DataCase, async: false
  use Oban.Testing, repo: PatchwritApi.Repo

  alias PatchwritApi.Analyses
  alias PatchwritApi.Findings
  alias PatchwritApi.Tribunal
  alias PatchwritApi.Tribunal.Investigator
  alias PatchwritApi.Workers.InvestigateAnalysis
  alias PatchwritApi.Workers.RunTribunalCase

  @stub PatchwritApi.TribunalWorkerStub

  @opinion_json Jason.encode!(%{
                  "summary" => "Argued from the dossier.",
                  "arguments" => [
                    %{"text" => "The artifact is present", "evidence_ids" => ["artifact"]}
                  ],
                  "uncertainties" => []
                })

  @verdict_json Jason.encode!(%{
                  "presence" => "confirmed",
                  "application_relevance" => "unknown",
                  "exploitability" => "unknown",
                  "priority" => "high",
                  "recommendation" => "investigate_usage",
                  "supporting_evidence_ids" => ["artifact"],
                  "counter_evidence_ids" => ["missing_context"],
                  "missing_context" => [],
                  "rationale" => "Presence proven; exploitability not."
                })

  setup do
    Req.Test.set_req_test_to_shared()
    previous_meta = Application.get_env(:patchwrit_api, :meta)

    Application.put_env(:patchwrit_api, :meta,
      api_key: "test-key",
      base_url: "https://api.meta.ai/v1",
      req_options: [plug: {Req.Test, @stub}]
    )

    on_exit(fn ->
      if previous_meta,
        do: Application.put_env(:patchwrit_api, :meta, previous_meta),
        else: Application.delete_env(:patchwrit_api, :meta)
    end)

    Req.Test.stub(@stub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)
      system = payload["instructions"] || ""

      content =
        if String.contains?(system, "You are the Judge"), do: @verdict_json, else: @opinion_json

      Req.Test.json(conn, %{
        "model" => "stub-model",
        "output" => [
          %{"type" => "message", "content" => [%{"type" => "output_text", "text" => content}]}
        ],
        "usage" => %{"input_tokens" => 9, "output_tokens" => 1, "total_tokens" => 10}
      })
    end)

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

    {:ok, analysis: analysis}
  end

  test "worker runs prosecutor, defender, and judge exactly once", %{analysis: analysis} do
    {:ok, [case_record]} = Investigator.investigate_analysis(analysis)
    job = %Oban.Job{args: %{"case_id" => case_record.id}}

    assert :ok = RunTribunalCase.perform(job)
    assert length(Tribunal.list_opinions_for_case(case_record.id)) == 2
    assert [verdict] = Tribunal.list_verdicts_for_case(case_record.id)
    assert verdict.status == "completed"
    assert Tribunal.get_case(case_record.id).status == "verdict_ready"

    # The whole run is on the audit trail, in order.
    event_names =
      case_record.id
      |> Tribunal.list_audit_events_for_case()
      |> Enum.map(& &1.event)

    assert event_names == [
             "case_created",
             "tribunal_started",
             "opinion_completed",
             "opinion_completed",
             "verdict_completed",
             "policy_applied",
             "tribunal_completed"
           ]

    # Idempotent: a duplicate job must not re-argue or re-judge.
    assert :ok = RunTribunalCase.perform(job)
    assert length(Tribunal.list_opinions_for_case(case_record.id)) == 2
    assert length(Tribunal.list_verdicts_for_case(case_record.id)) == 1
  end

  test "investigation enqueues tribunal jobs for triage-selected cases only", %{
    analysis: analysis
  } do
    assert :ok = InvestigateAnalysis.perform(%Oban.Job{args: %{"analysis_id" => analysis.id}})

    [case_record] = Tribunal.list_cases_for_analysis(analysis.id)
    assert_enqueued(worker: RunTribunalCase, args: %{"case_id" => case_record.id})
  end

  test "missing case is cancelled, not retried" do
    job = %Oban.Job{args: %{"case_id" => Ecto.UUID.generate()}}
    assert {:cancel, "case not found"} = RunTribunalCase.perform(job)
  end
end
