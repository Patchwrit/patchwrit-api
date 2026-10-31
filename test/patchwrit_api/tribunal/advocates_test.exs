defmodule PatchwritApi.Tribunal.AdvocatesTest do
  use PatchwritApi.DataCase, async: false

  alias PatchwritApi.Analyses
  alias PatchwritApi.Findings
  alias PatchwritApi.Tribunal
  alias PatchwritApi.Tribunal.Advocates
  alias PatchwritApi.Tribunal.Investigator

  @stub PatchwritApi.AdvocatesStub

  @prosecutor_json Jason.encode!(%{
                     "summary" => "Urgent: a directly reachable-era log4j with a known RCE.",
                     "arguments" => [
                       %{
                         "text" => "log4j-core 2.14.1 is present and direct",
                         "evidence_ids" => ["artifact", "advisory:GHSA-jfh8-c2jp-5v3q", "path:0"]
                       }
                     ],
                     "uncertainties" => ["code reachability not evaluated"]
                   })

  @defender_json Jason.encode!(%{
                   "summary" => "Presence is proven; exploitability is not.",
                   "arguments" => [
                     %{
                       "text" => "Reachability remains unknown in the dossier",
                       "evidence_ids" => ["missing_context", "graph"]
                     }
                   ],
                   "uncertainties" => []
                 })

  setup do
    Req.Test.set_req_test_to_shared()

    previous_meta = Application.get_env(:patchwrit_api, :meta)
    Application.put_env(:patchwrit_api, :advocate_stub_mode, :valid)

    Application.put_env(:patchwrit_api, :meta,
      api_key: "test-key",
      base_url: "https://api.meta.ai/v1",
      req_options: [plug: {Req.Test, @stub}]
    )

    on_exit(fn ->
      Application.delete_env(:patchwrit_api, :advocate_stub_mode)

      if previous_meta,
        do: Application.put_env(:patchwrit_api, :meta, previous_meta),
        else: Application.delete_env(:patchwrit_api, :meta)
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

    {:ok, [case_record]} = Investigator.investigate_analysis(analysis)
    {:ok, case_record: case_record}
  end

  defp stub_advocates(parent) do
    Req.Test.stub(@stub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)

      text =
        (payload["instructions"] || "") <>
          Enum.map_join(payload["input"] || [], "\n", & &1["content"])

      role =
        if String.contains?(text, "YOUR ROLE: DEFENDER"), do: "defender", else: "prosecutor"

      send(parent, {:advocate_request, role, payload})

      content =
        case {role, Application.get_env(:patchwrit_api, :advocate_stub_mode)} do
          {"prosecutor", :fabricated} ->
            Jason.encode!(%{
              "summary" => "Trust me.",
              "arguments" => [%{"text" => "Secret proof", "evidence_ids" => ["evidence:secret"]}],
              "uncertainties" => []
            })

          {_role, :malformed} ->
            "this is not json"

          {"prosecutor", :uncited} ->
            Jason.encode!(%{
              "summary" => "Sounds bad.",
              "arguments" => [%{"text" => "No proof offered", "evidence_ids" => []}],
              "uncertainties" => []
            })

          {"prosecutor", _} ->
            @prosecutor_json

          {"defender", _} ->
            @defender_json
        end

      Req.Test.json(conn, %{
        "model" => "muse-spark-1.3",
        "output" => [
          %{"type" => "message", "content" => [%{"type" => "output_text", "text" => content}]}
        ],
        "usage" => %{"input_tokens" => 40, "output_tokens" => 2, "total_tokens" => 42}
      })
    end)
  end

  test "exchange persists validated prosecutor + defender and advances the case", %{
    case_record: case_record
  } do
    stub_advocates(self())

    assert {:ok, %{prosecutor: prosecutor, defender: defender}} =
             Advocates.run_exchange(case_record)

    assert prosecutor.role == "prosecutor"
    assert prosecutor.status == "completed"
    assert prosecutor.snapshot_hash == case_record.snapshot_hash
    assert prosecutor.model == "muse-spark-1.3"
    assert prosecutor.usage["total_tokens"] == 42
    assert "advisory:GHSA-jfh8-c2jp-5v3q" in prosecutor.citations

    assert defender.role == "defender"
    assert defender.status == "completed"

    assert defender.citations == ["graph", "missing_context"] or
             defender.citations == ["missing_context", "graph"]

    assert Tribunal.get_case(case_record.id).status == "opinions_ready"
    assert length(Tribunal.list_opinions_for_case(case_record.id)) == 2

    # The Defender saw the Prosecutor's validated summary.
    assert_received {:advocate_request, "defender", defender_payload}
    user_content = List.last(defender_payload["input"])["content"]
    assert user_content =~ "PROSECUTOR OPINION"
    assert user_content =~ "Urgent: a directly reachable-era log4j"
  end

  test "fabricated citation persists a failed opinion and stops the exchange", %{
    case_record: case_record
  } do
    Application.put_env(:patchwrit_api, :advocate_stub_mode, :fabricated)
    stub_advocates(self())

    assert {:error, opinion} = Advocates.run_exchange(case_record)
    assert opinion.status == "failed"
    assert opinion.error =~ "fabricated"
    assert opinion.error =~ "evidence:secret"

    opinions = Tribunal.list_opinions_for_case(case_record.id)
    assert length(opinions) == 1
    assert Tribunal.get_case(case_record.id).status == "evidence_ready"
  end

  test "uncited arguments persist a failed opinion (observed live: empty evidence_ids)", %{
    case_record: case_record
  } do
    Application.put_env(:patchwrit_api, :advocate_stub_mode, :uncited)
    stub_advocates(self())

    assert {:error, opinion} = Advocates.run_prosecutor(case_record)
    assert opinion.status == "failed"
    assert opinion.error =~ "cited no evidence"
  end

  test "malformed model output persists a failed opinion, never a silent pass", %{
    case_record: case_record
  } do
    Application.put_env(:patchwrit_api, :advocate_stub_mode, :malformed)
    stub_advocates(self())

    assert {:error, opinion} = Advocates.run_prosecutor(case_record)
    assert opinion.status == "failed"
    assert opinion.error =~ "not valid JSON"
    assert opinion.raw_content == "this is not json"
  end
end
