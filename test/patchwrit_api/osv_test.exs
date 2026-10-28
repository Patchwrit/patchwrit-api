defmodule PatchwritApi.OsvTest do
  use PatchwritApi.DataCase, async: false

  alias PatchwritApi.Analyses
  alias PatchwritApi.Findings
  alias PatchwritApi.Osv

  @stub PatchwritApi.OsvStub

  @log4j %{
    "group_id" => "org.apache.logging.log4j",
    "artifact_id" => "log4j-core",
    "version" => "2.14.1",
    "scope" => "compile",
    "depth" => 1,
    "introduced_via" => ["com.example:app:1.0"]
  }

  setup do
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

    {:ok, analysis} =
      Analyses.create_analysis(%{
        "repository_url" => "https://github.com/example/app",
        "status" => "completed",
        "result" => %{"dependencies" => [@log4j]}
      })

    {:ok, analysis: analysis}
  end

  test "persists findings and stamps the scan time", %{analysis: analysis} do
    stub_hit()

    assert {:ok, updated} = Osv.scan_analysis(analysis)
    assert updated.osv_scanned_at

    assert [finding] = Findings.list_findings_for_analysis(analysis.id)
    assert finding.osv_id == "GHSA-jfh8-c2jp-5v3q"
    assert finding.package_name == "org.apache.logging.log4j:log4j-core"
    assert finding.raw["aliases"] == ["CVE-2021-44228"]
  end

  test "a zero-hit scan still records that it ran", %{analysis: analysis} do
    Req.Test.stub(@stub, fn conn -> Req.Test.json(conn, %{"results" => [%{}]}) end)

    assert {:ok, updated} = Osv.scan_analysis(analysis)
    assert updated.osv_scanned_at
    assert Findings.list_findings_for_analysis(analysis.id) == []
  end

  test "rescanning replaces findings instead of duplicating them", %{analysis: analysis} do
    stub_hit()

    assert {:ok, _} = Osv.scan_analysis(analysis)
    assert {:ok, _} = Osv.scan_analysis(Analyses.get_analysis!(analysis.id))
    assert Findings.count_findings_for_analysis(analysis.id) == 1
  end

  test "an OSV error leaves findings and scan time untouched", %{analysis: analysis} do
    Req.Test.stub(@stub, fn conn ->
      conn |> Plug.Conn.put_status(503) |> Req.Test.json(%{})
    end)

    assert {:error, _message} = Osv.scan_analysis(analysis)
    refute Analyses.get_analysis!(analysis.id).osv_scanned_at
    assert Findings.list_findings_for_analysis(analysis.id) == []
  end

  defp stub_hit do
    Req.Test.stub(@stub, fn conn ->
      case conn.request_path do
        "/v1/querybatch" ->
          Req.Test.json(conn, %{"results" => [%{"vulns" => [%{"id" => "GHSA-jfh8-c2jp-5v3q"}]}]})

        "/v1/vulns/GHSA-jfh8-c2jp-5v3q" ->
          Req.Test.json(conn, %{
            "id" => "GHSA-jfh8-c2jp-5v3q",
            "summary" => "Apache Log4j2 vulnerable to RCE via JNDI",
            "aliases" => ["CVE-2021-44228"],
            "severity" => [%{"type" => "CVSS_V3", "score" => "CVSS:3.1/AV:N"}],
            "affected" => [
              %{
                "package" => %{
                  "name" => "org.apache.logging.log4j:log4j-core",
                  "ecosystem" => "Maven"
                },
                "ranges" => [
                  %{"type" => "ECOSYSTEM", "events" => [%{"fixed" => "2.17.0"}]}
                ]
              }
            ]
          })
      end
    end)
  end
end
