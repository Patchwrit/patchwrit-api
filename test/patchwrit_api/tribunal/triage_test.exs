defmodule PatchwritApi.Tribunal.TriageTest do
  use ExUnit.Case, async: true

  alias PatchwritApi.Tribunal.Case
  alias PatchwritApi.Tribunal.Triage

  defp case_for(group, artifact, opts) do
    packet = %{
      "artifact" => %{
        "group_id" => group,
        "artifact_id" => artifact,
        "direct" => Keyword.get(opts, :direct, false),
        "scope" => Keyword.get(opts, :scope, "compile")
      },
      "advisories" => [
        %{
          "id" => Keyword.get(opts, :advisory, "GHSA-x"),
          "severity" => Keyword.get(opts, :severity, "HIGH")
        }
      ]
    }

    %Case{packet: packet, dossier_snapshot: packet}
  end

  test "eligible: direct or compile/runtime scope, with reported severity" do
    assert Triage.eligible?(case_for("g", "direct-test", direct: true, scope: "test"))
    assert Triage.eligible?(case_for("g", "compile-transitive", scope: "compile"))
    assert Triage.eligible?(case_for("g", "runtime-transitive", scope: "runtime"))
    refute Triage.eligible?(case_for("g", "test-transitive", scope: "test"))
    refute Triage.eligible?(case_for("g", "provided", scope: "provided"))
    refute Triage.eligible?(case_for("g", "no-severity", direct: true, severity: nil))
  end

  test "deterministic order: direct first, then package and advisory" do
    transitive = case_for("a", "aaa", scope: "compile")
    direct = case_for("z", "zzz", direct: true)
    selected = Triage.select_cases([transitive, direct])
    assert Enum.map(selected, & &1.packet["artifact"]["artifact_id"]) == ["zzz", "aaa"]
  end

  test "caps the selection at the limit (default 10)" do
    cases =
      for i <- 1..12 do
        case_for("g", "art-#{String.pad_leading(Integer.to_string(i), 2, "0")}", direct: true)
      end

    assert length(Triage.select_cases(cases)) == 10
    assert length(Triage.select_cases(cases, 3)) == 3
    assert Triage.default_limit() == 10
  end
end
