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
      "schema_version" => 2,
      "dossier_version" => 2,
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
        "module" => dep && dep["module"],
        "pom_path" => dep && dep["pom_path"],
        "depth" => dep && dep["depth"],
        "direct" => direct?(dep),
        "introduction_paths" => dep_introduction_paths(dep)
      },
      "advisories" => [
        %{
          "source" => "OSV",
          "id" => finding.osv_id,
          "aliases" => finding.aliases,
          "summary" => finding.summary,
          "severity" => finding.severity,
          "fixed_versions" => finding.fixed_versions,
          "affected_ranges" => advisory_affected_ranges(finding),
          "references" => advisory_references(finding),
          "affected" => "reported",
          "reachability" => "unknown"
        }
      ],
      "graph" => graph_block(analysis),
      "evidence" => evidence_index(dep, finding, analysis),
      "collection" => %{
        "tools" => ["maven-dependency-plugin:3.8.1", "osv-api"],
        "worker_image" => analysis.worker_image,
        "osv_scanned_at" => iso8601(analysis.osv_scanned_at),
        "observed_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> iso8601()
      },
      "missing_context" => missing_context(dep, finding, analysis)
    }
  end

  @doc """
  (Re)builds cases for every finding of the analysis. Rebuilding
  replaces the analysis's cases wholesale, matching scan semantics.
  Each case freezes its dossier into `dossier_snapshot` (versioned and
  hashed) at build time; tribunal stages must read the snapshot.
  """
  def investigate_analysis(%Analysis{} = analysis) do
    case_attrs =
      Enum.map(Findings.list_findings_for_analysis(analysis.id), fn finding ->
        packet = build_packet(analysis, finding)

        %{
          "analysis_id" => analysis.id,
          "finding_id" => finding.id,
          "status" => "evidence_ready",
          "packet" => packet,
          "dossier_version" => packet["dossier_version"],
          "dossier_snapshot" => packet,
          "snapshot_hash" => snapshot_hash(packet)
        }
      end)

    {:ok, cases} = Tribunal.replace_cases(analysis, case_attrs)

    Enum.each(cases, fn case_record ->
      Tribunal.record_audit_event(case_record, "case_created", "investigator", %{
        "finding_id" => case_record.finding_id,
        "snapshot_hash" => case_record.snapshot_hash,
        "dossier_version" => case_record.dossier_version
      })
    end)

    {:ok, cases}
  end

  @doc "Stable SHA-256 fingerprint of a dossier packet."
  def snapshot_hash(packet) do
    :crypto.hash(:sha256, :erlang.term_to_binary(packet))
    |> Base.encode16(case: :lower)
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

  defp dep_introduction_paths(nil), do: []

  defp dep_introduction_paths(dep) do
    case dep["introduction_paths"] do
      [_ | _] = paths -> paths
      _ -> [dep["introduced_via"] || []]
    end
  end

  defp dep_introduction_path(dep), do: dep_introduction_paths(dep) |> List.first([])

  # -- packet pieces -------------------------------------------------------

  # Stable evidence IDs the tribunal may cite. Phoenix validates model
  # citations against exactly this set for the snapshotted version.
  defp evidence_index(dep, finding, analysis) do
    paths = dep_introduction_paths(dep)

    base = [
      %{"id" => "source", "kind" => "source"},
      %{"id" => "artifact", "kind" => "artifact"},
      %{"id" => "advisory:#{finding.osv_id}", "kind" => "advisory"},
      %{"id" => "graph", "kind" => "graph_completeness"},
      %{"id" => "collection", "kind" => "collection_provenance"}
    ]

    path_entries =
      paths
      |> Enum.with_index()
      |> Enum.map(fn {_path, i} -> %{"id" => "path:#{i}", "kind" => "introduction_path"} end)

    base ++ path_entries ++ missing_entries(analysis)
  end

  defp missing_entries(_analysis), do: [%{"id" => "missing_context", "kind" => "missing_context"}]

  defp graph_block(analysis) do
    case get_in(analysis.result || %{}, ["graph"]) do
      %{} = graph -> Map.put(graph, "status", "reported")
      _ -> %{"status" => "unknown", "complete" => false}
    end
  end

  # Affected version ranges for this finding's package, extracted from
  # the raw OSV entry (ranges are evidence; the summary is not).
  defp advisory_affected_ranges(finding) do
    (finding.raw["affected"] || [])
    |> Enum.filter(fn affected ->
      get_in(affected, ["package", "name"]) == finding.package_name and
        get_in(affected, ["package", "ecosystem"]) == "Maven"
    end)
    |> Enum.flat_map(fn affected ->
      Enum.map(affected["ranges"] || [], fn range ->
        %{"type" => range["type"], "events" => range["events"] || []}
      end)
    end)
  end

  defp advisory_references(finding) do
    (finding.raw["references"] || [])
    |> Enum.map(& &1["url"])
    |> Enum.reject(&is_nil/1)
  end

  defp missing_context(dep, finding, analysis) do
    base = ["code_reachability_not_evaluated", "source_level_evidence_not_collected"]

    base
    |> add_if(not graph_complete?(analysis), "dependency_graph_incomplete")
    |> add_if(is_nil(dep), "dependency_record_not_found")
    |> add_if(dep && dep_introduction_path(dep) == [], "introduction_path_unavailable")
    |> add_if(finding.fixed_versions == [], "no_fixed_version_published")
    |> add_if(is_nil(finding.severity), "severity_not_reported")
  end

  # Only an explicit v2 graph block can prove completeness; a missing
  # block (legacy result) is unknown, which counts as incomplete.
  defp graph_complete?(analysis) do
    get_in(analysis.result || %{}, ["graph", "complete"]) == true
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
