defmodule PatchwritApi.Analyses.Sbom do
  @moduledoc """
  CycloneDX SBOM generation from a persisted worker result.

  The SBOM is exactly the resolved graph Patchwrit observed — unique
  coordinates with Maven scope mapped to CycloneDX scope, package
  URLs, and Patchwrit provenance properties (depth, modules, direct).
  Nothing is added, inferred, or beautified: an incomplete graph
  produces an SBOM of the observed subset, and the analysis page says
  so beside the download.
  """

  alias PatchwritApi.Analyses.Analysis
  alias PatchwritApi.Analyses.DependencyGraph

  @scope_map %{
    "compile" => "required",
    "runtime" => "required",
    "system" => "required",
    "test" => "optional",
    "provided" => "optional",
    "import" => "optional"
  }

  @doc "Builds the CycloneDX 1.5 document (as a map) for an analysis."
  def cyclonedx(%Analysis{} = analysis) do
    dependencies = get_in(analysis.result || %{}, ["dependencies"]) || []

    rows =
      dependencies
      |> DependencyGraph.aggregate()
      |> Enum.filter(&(&1.min_depth >= 1))

    %{
      "bomFormat" => "CycloneDX",
      "specVersion" => "1.5",
      "version" => 1,
      "metadata" => %{
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
        "tools" => [%{"vendor" => "Patchwrit", "name" => "patchwrit-api"}],
        "component" => %{
          "type" => "application",
          "name" => analysis.repository_url,
          "version" => analysis.resolved_sha,
          "properties" => [
            %{"name" => "patchwrit:analysis_id", "value" => analysis.id},
            %{"name" => "patchwrit:requested_ref", "value" => to_string(analysis.requested_ref)},
            graph_property(analysis)
          ]
        }
      },
      "components" => Enum.map(rows, &component(&1, dependencies))
    }
  end

  defp graph_property(analysis) do
    graph = analysis.result && analysis.result["graph"]

    value =
      cond do
        is_map(graph) and graph["complete"] ->
          "complete (#{graph["modules_resolved"]}/#{graph["modules_total"]} modules)"

        is_map(graph) ->
          "partial (#{graph["modules_resolved"]}/#{graph["modules_total"]} modules)"

        true ->
          "unknown"
      end

    %{"name" => "patchwrit:graph_completeness", "value" => value}
  end

  defp component(row, dependencies) do
    [group, artifact, version] = split_coordinate(row.coordinate)

    %{
      "type" => "library",
      "group" => group,
      "name" => artifact,
      "version" => version,
      "scope" => cyclonedx_scope(row.scopes),
      "purl" => "pkg:maven/#{group}/#{artifact}@#{version}",
      "properties" =>
        [
          %{"name" => "patchwrit:direct", "value" => to_string(row.direct)},
          %{"name" => "patchwrit:min_depth", "value" => Integer.to_string(row.min_depth)},
          %{"name" => "patchwrit:occurrences", "value" => Integer.to_string(row.occurrences)}
        ] ++
          module_properties(row) ++
          path_properties(row, dependencies)
    }
  end

  defp module_properties(%{modules: []}), do: []

  defp module_properties(%{modules: modules}) do
    [%{"name" => "patchwrit:modules", "value" => Enum.join(modules, ",")}]
  end

  defp path_properties(row, _dependencies) do
    [
      %{
        "name" => "patchwrit:introduction_paths",
        "value" => Integer.to_string(row.path_count)
      }
    ]
  end

  defp cyclonedx_scope(scopes) do
    cond do
      "required" in Enum.map(scopes, &Map.get(@scope_map, &1, "required")) -> "required"
      scopes == [] -> "required"
      true -> "optional"
    end
  end

  defp split_coordinate(coordinate) do
    parts = String.split(coordinate, ":")
    [Enum.at(parts, 0), Enum.at(parts, 1), Enum.at(parts, 2)]
  end
end
