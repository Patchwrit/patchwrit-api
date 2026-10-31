defmodule PatchwritApi.Tribunal.JudgeTest do
  use PatchwritApi.DataCase, async: false

  alias PatchwritApi.Analyses
  alias PatchwritApi.Findings
  alias PatchwritApi.Tribunal
  alias PatchwritApi.Tribunal.Advocates
  alias PatchwritApi.Tribunal.Investigator
  alias PatchwritApi.Tribunal.Judge
  alias PatchwritApi.Tribunal.PolicyGate

  @stub PatchwritApi.JudgeStub

  @opinion_json Jason.encode!(%{
                  "summary" => "Argued from the dossier.",
                  "arguments" => [
                    %{"text" => "The artifact is present", "evidence_ids" => ["artifact"]}
                  ],
                  "uncertainties" => ["reachability unknown"]
                })

  @verdict_json Jason.encode!(%{
                  "presence" => "confirmed",
                  "application_relevance" => "unknown",
                  "exploitability" => "unknown",
                  "priority" => "high",
                  "recommendation" => "remediate_now",
                  "supporting_evidence_ids" => ["artifact", "advisory:GHSA-jfh8-c2jp-5v3q"],
                  "counter_evidence_ids" => ["missing_context"],
                  "missing_context" => ["code_reachability_not_evaluated"],
                  "rationale" => "Presence is proven; exploitability is not."
                })

  setup do
    Req.Test.set_req_test_to_shared()
    previous_meta = Application.get_env(:patchwrit_api, :meta)
    Application.put_env(:patchwrit_api, :judge_stub_mode, :valid)

    Application.put_env(:patchwrit_api, :meta,
      api_key: "test-key",
      base_url: "https://api.meta.ai/v1",
      req_options: [plug: {Req.Test, @stub}]
    )

    on_exit(fn ->
      Application.delete_env(:patchwrit_api, :judge_stub_mode)

      if previous_meta,
        do: Application.put_env(:patchwrit_api, :meta, previous_meta),
        else: Application.delete_env(:patchwrit_api, :meta)
    end)

    :ok
  end

  defp build_case(graph) do
    result = %{
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

    result = if graph, do: Map.put(result, "graph", graph), else: result

    {:ok, analysis} =
      Analyses.create_analysis(%{
        "repository_url" => "https://github.com/example/app",
        "requested_ref" => "main",
        "jdk_version" => "17",
        "resolved_sha" => "0123456789abcdef0123456789abcdef01234567",
        "worker_image" => "ghcr.io/patchwrit/patchwrit-worker@sha256:abc",
        "status" => "completed",
        "result" => result
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
    case_record
  end

  defp stub_all do
    Req.Test.stub(@stub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)
      system = payload["instructions"] || ""

      content =
        cond do
          String.contains?(system, "You are the Judge") ->
            case Application.get_env(:patchwrit_api, :judge_stub_mode) do
              :fabricated ->
                Jason.encode!(%{
                  "presence" => "confirmed",
                  "application_relevance" => "unknown",
                  "exploitability" => "unknown",
                  "priority" => "high",
                  "recommendation" => "dismiss",
                  "supporting_evidence_ids" => ["evidence:invented"],
                  "counter_evidence_ids" => [],
                  "missing_context" => [],
                  "rationale" => "Made up."
                })

              _ ->
                @verdict_json
            end

          true ->
            @opinion_json
        end

      Req.Test.json(conn, %{
        "model" => "stub-model",
        "output" => [
          %{"type" => "message", "content" => [%{"type" => "output_text", "text" => content}]}
        ],
        "usage" => %{"input_tokens" => 90, "output_tokens" => 9, "total_tokens" => 99}
      })
    end)
  end

  defp argued_case(graph \\ nil) do
    stub_all()
    case_record = build_case(graph)
    {:ok, _opinions} = Advocates.run_exchange(case_record)
    case_record
  end

  describe "policy gate (deterministic)" do
    test "complete graph leaves the recommendation untouched" do
      gate = PolicyGate.apply_gate("remediate_now", %{"graph" => %{"complete" => true}})
      assert gate.recommendation == "remediate_now"
      assert gate.policy_capped == false
      assert gate.policy_notes == []
    end

    test "unknown graph caps at needs_human_review" do
      gate = PolicyGate.apply_gate("remediate_now", %{"graph" => %{"complete" => false}})
      assert gate.recommendation == "needs_human_review"
      assert gate.policy_capped == true
      assert hd(gate.policy_notes) =~ "incomplete evidence"
    end

    test "missing graph block also caps; already-capped is noted, not double-capped" do
      gate = PolicyGate.apply_gate("needs_human_review", %{})
      assert gate.recommendation == "needs_human_review"
      assert gate.policy_capped == false
      assert gate.policy_notes != []
    end
  end

  test "judge verdict is policy-capped when graph completeness is unknown" do
    case_record = argued_case()

    assert {:ok, verdict} = Judge.run_verdict(case_record)
    assert verdict.status == "completed"
    assert verdict.model == "muse-wonder-1.0"
    assert verdict.snapshot_hash == case_record.snapshot_hash
    assert verdict.presence == "confirmed"
    assert verdict.exploitability == "unknown"
    assert verdict.judge_recommendation == "remediate_now"
    # The gate, not the model, has the final word.
    assert verdict.recommendation == "needs_human_review"
    assert verdict.policy_capped == true
    assert verdict.usage["total_tokens"] == 99
    assert Tribunal.get_case(case_record.id).status == "verdict_ready"
  end

  test "judge verdict stands when the graph is explicitly complete" do
    case_record =
      argued_case(%{"complete" => true, "modules_total" => 1, "modules_resolved" => 1})

    assert {:ok, verdict} = Judge.run_verdict(case_record)
    assert verdict.recommendation == "remediate_now"
    assert verdict.policy_capped == false
    assert verdict.policy_notes == []
  end

  test "fabricated judge citation persists a failed verdict" do
    Application.put_env(:patchwrit_api, :judge_stub_mode, :fabricated)
    case_record = argued_case()

    assert {:error, verdict} = Judge.run_verdict(case_record)
    assert verdict.status == "failed"
    assert verdict.error =~ "fabricated"
    assert Tribunal.get_case(case_record.id).status == "opinions_ready"
  end

  test "cannot judge before both advocates completed" do
    stub_all()
    case_record = build_case(nil)

    assert {:error, message} = Judge.run_verdict(case_record)
    assert message =~ "no completed prosecutor opinion"
    assert Tribunal.list_verdicts_for_case(case_record.id) == []
  end
end
