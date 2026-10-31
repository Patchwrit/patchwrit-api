defmodule PatchwritApi.Tribunal.AuditTrailTest do
  use PatchwritApi.DataCase, async: false

  alias PatchwritApi.Analyses
  alias PatchwritApi.Findings
  alias PatchwritApi.Tribunal
  alias PatchwritApi.Tribunal.Investigator

  defp seed_case do
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

    {:ok, _analysis} =
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

  test "investigation records a case_created audit event with the snapshot hash" do
    case_record = seed_case()

    assert [event] = Tribunal.list_audit_events_for_case(case_record.id)
    assert event.event == "case_created"
    assert event.actor == "investigator"
    assert event.analysis_id == case_record.analysis_id
    assert event.metadata["snapshot_hash"] == case_record.snapshot_hash
    assert event.metadata["finding_id"] == case_record.finding_id
  end

  test "record_audit_event validates event and actor vocabularies" do
    case_record = seed_case()

    assert {:error, changeset} =
             Tribunal.record_audit_event(case_record, "made_up_event", "system", %{})

    assert %{event: _} = errors_on(changeset)

    assert {:error, changeset} =
             Tribunal.record_audit_event(case_record, "tribunal_started", "nobody", %{})

    assert %{actor: _} = errors_on(changeset)

    # The failed writes did not break anything, and the seeded
    # case_created event is still the only one.
    assert length(Tribunal.list_audit_events_for_case(case_record.id)) == 1
  end

  test "events list in insertion order with their metadata" do
    case_record = seed_case()

    {:ok, _} =
      Tribunal.record_audit_event(case_record, "tribunal_queued", "operator", %{
        "source" => "manual",
        "advocate_model" => "muse-spark-1.3"
      })

    {:ok, _} = Tribunal.record_audit_event(case_record, "tribunal_started", "system", %{})

    events = Tribunal.list_audit_events_for_case(case_record.id)
    assert Enum.map(events, & &1.event) == ["case_created", "tribunal_queued", "tribunal_started"]

    queued = Enum.at(events, 1)
    assert queued.actor == "operator"
    assert queued.metadata["source"] == "manual"
    assert queued.metadata["advocate_model"] == "muse-spark-1.3"
  end

  test "usage_summary keeps totals and the cached/reasoning splits only" do
    assert Tribunal.usage_summary(%{
             "total_tokens" => 100,
             "prompt_tokens" => 70,
             "completion_tokens" => 30,
             "prompt_tokens_details" => %{"cached_tokens" => 40},
             "completion_tokens_details" => %{"reasoning_tokens" => 25}
           }) == %{
             "total_tokens" => 100,
             "prompt_tokens" => 70,
             "completion_tokens" => 30,
             "cached_tokens" => 40,
             "reasoning_tokens" => 25
           }

    assert Tribunal.usage_summary(%{"total_tokens" => 5}) == %{"total_tokens" => 5}
    assert Tribunal.usage_summary(%{}) == %{}
    assert Tribunal.usage_summary(nil) == %{}
  end
end
