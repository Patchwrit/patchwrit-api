defmodule PatchwritApi.Tribunal.Investigator do
  @moduledoc """
  The Investigator: builds a deterministic evidence packet per finding.

  Facts only — every value comes from tool-observed records (the worker
  result, the persisted dependency graph, the OSV advisory). No model
  is called. What the evidence cannot establish is stated explicitly:
  `reachability` starts as `"unknown"` and `missing_context` lists the
  gaps (code reachability has not been evaluated, no source-level
  evidence has been collected). A later agent may argue from this
  packet; it may not silently upgrade these flags.
  """

  alias PatchwritApi.Analyses.Analysis
  alias PatchwritApi.Findings
  alias PatchwritApi.Findings.Finding
  alias PatchwritApi.Tribunal

  @doc "Builds the evidence packet for one finding of an analysis."
  def build_packet(%Analysis{} = analysis, %Finding{} = finding) do
    dep = find_dependency(analysis, finding)
    [group_id, artifact_id] = split_package_name(finding.package_name)

    %{
      "schema_version" => 1,
      "source" => %{
        "repository_url" => analysis.repository_url,
        "commit_sha" => analysis.resolved_sha,
        "requested_ref" => analysis.requested_ref,
        "jdk" => analysis.jdk_version
      },
      "artifact" => %{
        "ecosystem" => "Maven",
        "group_id" => group_id,
        "artifact_id" => artifact_id,
        "resolved_version" => finding.package_version,
        "scope" => dep && dep["scope"],
        "depth" => dep && dep["depth"],
        "direct" => direct?(dep),
        "introduction_paths" => [dep_introduction_path(dep)]
      },
      "advisories" => [
        %{
          "source" => "OSV",
          "id" => finding.osv_id,
          "aliases" => finding.aliases,
          "summary" => finding.summary,
          "severity" => finding.severity,
          "fixed_versions" => finding.fixed_versions,
          "references" => advisory_references(finding),
          "affected" => "reported",
          "reachability" => "unknown"
        }
      ],
      "collection" => %{
        "tools" => ["maven-dependency-plugin:3.8.1", "osv-api"],
        "worker_image" => analysis.worker_image,
        "osv_scanned_at" => iso8601(analysis.osv_scanned_at),
        "observed_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> iso8601()
      },
      "missing_context" => missing_context(dep, finding)
    }
  end

  @doc """
  (Re)builds cases for every finding of the analysis. Rebuilding
  replaces the analysis's cases wholesale, matching scan semantics.
  """
  def investigate_analysis(%Analysis{} = analysis) do
    case_attrs =
      Enum.map(Findings.list_findings_for_analysis(analysis.id), fn finding ->
        %{
          "analysis_id" => analysis.id,
          "finding_id" => finding.id,
          "status" => "evidence_ready",
          "packet" => build_packet(analysis, finding)
        }
      end)

    Tribunal.replace_cases(analysis, case_attrs)
  end

  # -- dependency linkage -------------------------------------------------

  defp find_dependency(analysis, finding) do
    dependencies = get_in(analysis.result || %{}, ["dependencies"]) || []

    Enum.find(dependencies, fn dep ->
      "#{dep["group_id"]}:#{dep["artifact_id"]}" == finding.package_name and
        dep["version"] == finding.package_version
    end)
  end

  defp direct?(%{"depth" => 1}), do: true
  defp direct?(_dep), do: false

  defp dep_introduction_path(nil), do: []
  defp dep_introduction_path(dep), do: dep["introduced_via"] || []

  # -- packet pieces -------------------------------------------------------

  defp advisory_references(finding) do
    (finding.raw["references"] || [])
    |> Enum.map(& &1["url"])
    |> Enum.reject(&is_nil/1)
  end

  defp missing_context(dep, finding) do
    base = ["code_reachability_not_evaluated", "source_level_evidence_not_collected"]

    base
    |> add_if(is_nil(dep), "dependency_record_not_found")
    |> add_if(dep && dep_introduction_path(dep) == [], "introduction_path_unavailable")
    |> add_if(finding.fixed_versions == [], "no_fixed_version_published")
    |> add_if(is_nil(finding.severity), "severity_not_reported")
  end

  defp add_if(list, true, item), do: list ++ [item]
  defp add_if(list, _false, _item), do: list

  defp split_package_name(name) do
    case String.split(name, ":", parts: 2) do
      [group_id, artifact_id] -> [group_id, artifact_id]
      [artifact_id] -> [nil, artifact_id]
    end
  end

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
end
