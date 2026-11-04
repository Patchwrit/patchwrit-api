defmodule PatchwritApi.Analyses.SbomTest do
  use ExUnit.Case, async: true

  alias PatchwritApi.Analyses.Analysis
  alias PatchwritApi.Analyses.Sbom

  defp analysis do
    %Analysis{
      id: "analysis-1",
      repository_url: "https://github.com/example/app",
      requested_ref: "main",
      resolved_sha: "0123456789abcdef0123456789abcdef01234567",
      result: %{
        "graph" => %{"complete" => true, "modules_total" => 1, "modules_resolved" => 1},
        "dependencies" => [
          %{
            "group_id" => "org.apache.logging.log4j",
            "artifact_id" => "log4j-core",
            "version" => "2.14.1",
            "scope" => "compile",
            "depth" => 1,
            "module" => "mod-a",
            "introduction_paths" => [
              ["com.example:app:1.0", "org.apache.logging.log4j:log4j-core:2.14.1"]
            ]
          },
          %{
            "group_id" => "junit",
            "artifact_id" => "junit",
            "version" => "4.13.2",
            "scope" => "test",
            "depth" => 2,
            "module" => "mod-a",
            "introduction_paths" => [["com.example:app:1.0", "junit:junit:4.13.2"]]
          }
        ]
      }
    }
  end

  test "emits CycloneDX with purls, mapped scopes, and provenance" do
    doc = Sbom.cyclonedx(analysis())

    assert doc["bomFormat"] == "CycloneDX"
    assert doc["specVersion"] == "1.5"
    assert doc["metadata"]["component"]["version"] =~ "0123456"

    by_name = Map.new(doc["components"], &{&1["name"], &1})
    log4j = by_name["log4j-core"]
    assert log4j["group"] == "org.apache.logging.log4j"
    assert log4j["purl"] == "pkg:maven/org.apache.logging.log4j/log4j-core@2.14.1"
    assert log4j["scope"] == "required"

    assert by_name["junit"]["scope"] == "optional"

    props = Map.new(log4j["properties"], &{&1["name"], &1["value"]})
    assert props["patchwrit:direct"] == "true"
    assert props["patchwrit:modules"] == "mod-a"
  end

  test "empty graph produces an empty, honest SBOM" do
    doc = Sbom.cyclonedx(%Analysis{repository_url: "https://github.com/example/x", result: %{}})
    assert doc["components"] == []
  end
end
