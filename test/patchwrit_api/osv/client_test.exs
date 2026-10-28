defmodule PatchwritApi.Osv.ClientTest do
  use ExUnit.Case, async: false

  alias PatchwritApi.Osv.Client

  @stub PatchwritApi.OsvStub

  @log4j %{
    "group_id" => "org.apache.logging.log4j",
    "artifact_id" => "log4j-core",
    "version" => "2.14.1",
    "scope" => "compile",
    "depth" => 1,
    "introduced_via" => ["com.example:app:1.0"]
  }
  @clean %{
    "group_id" => "org.apache.tomcat.embed",
    "artifact_id" => "tomcat-embed-core",
    "version" => "10.1.24",
    "scope" => "compile",
    "depth" => 2,
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

    :ok
  end

  test "returns finding attributes for vulnerable dependencies only" do
    stub_osv_with_log4j_hit()

    assert {:ok, [finding]} = Client.scan_dependencies([@log4j, @clean])
    assert finding["osv_id"] == "GHSA-jfh8-c2jp-5v3q"
    assert finding["package_name"] == "org.apache.logging.log4j:log4j-core"
    assert finding["package_version"] == "2.14.1"
    assert finding["severity"] =~ "CVSS:3.1"
    assert finding["fixed_versions"] == ["2.17.0"]
    assert finding["aliases"] == ["CVE-2021-44228"]
    assert finding["summary"] =~ "Log4j"
  end

  test "deduplicates repeated dependencies before querying" do
    stub_osv_with_log4j_hit()

    assert {:ok, [_finding]} = Client.scan_dependencies([@log4j, @log4j])
  end

  test "fails closed when OSV errors" do
    Req.Test.stub(@stub, fn conn ->
      conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"error" => "boom"})
    end)

    assert {:error, message} = Client.scan_dependencies([@log4j])
    assert message =~ "500"
  end

  defp stub_osv_with_log4j_hit do
    Req.Test.stub(@stub, fn conn ->
      case conn.request_path do
        "/v1/querybatch" ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          %{"queries" => queries} = Jason.decode!(body)

          results =
            Enum.map(queries, fn query ->
              if query["package"]["name"] == "org.apache.logging.log4j:log4j-core" do
                %{"vulns" => [%{"id" => "GHSA-jfh8-c2jp-5v3q"}]}
              else
                %{}
              end
            end)

          Req.Test.json(conn, %{"results" => results})

        "/v1/vulns/GHSA-jfh8-c2jp-5v3q" ->
          Req.Test.json(conn, %{
            "id" => "GHSA-jfh8-c2jp-5v3q",
            "summary" => "Apache Log4j2 vulnerable to RCE via JNDI",
            "aliases" => ["CVE-2021-44228"],
            "severity" => [
              %{
                "type" => "CVSS_V3",
                "score" => "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:C/C:H/I:H/A:H"
              }
            ],
            "affected" => [
              %{
                "package" => %{
                  "name" => "org.apache.logging.log4j:log4j-core",
                  "ecosystem" => "Maven"
                },
                "ranges" => [
                  %{
                    "type" => "ECOSYSTEM",
                    "events" => [%{"introduced" => "2.13.0"}, %{"fixed" => "2.17.0"}]
                  }
                ]
              }
            ]
          })
      end
    end)
  end
end
