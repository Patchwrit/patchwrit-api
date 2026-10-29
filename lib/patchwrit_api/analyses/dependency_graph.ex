defmodule PatchwritApi.Analyses.DependencyGraph do
  @moduledoc """
  Read models over the persisted Maven dependency graph.

  Impact is observed fan-in from the resolved trees: how many modules
  a dependency appears in and how many distinct introduction paths
  reach it. That is structural (build-graph) impact — not runtime
  usage, which Patchwrit does not measure yet.
  """

  @doc """
  Aggregates raw per-module dependency entries by coordinate.

  Each row: coordinate, modules it appears in, distinct introduction
  paths, shallowest depth, scopes, whether it is ever direct, and how
  many raw entries it aggregates. Sorted by impact: module spread,
  then path fan-in, then shallowest depth, then coordinate.
  """
  def aggregate(dependencies) when is_list(dependencies) do
    dependencies
    |> Enum.group_by(&coordinate/1)
    |> Enum.map(fn {coordinate, entries} ->
      paths =
        entries
        |> Enum.flat_map(&introduction_paths/1)
        |> Enum.reject(&(&1 == []))
        |> Enum.uniq()

      %{
        coordinate: coordinate,
        modules:
          entries
          |> Enum.map(& &1["module"])
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()
          |> Enum.sort(),
        module_count:
          entries |> Enum.map(& &1["module"]) |> Enum.reject(&is_nil/1) |> Enum.uniq() |> length(),
        paths: paths,
        path_count: length(paths),
        min_depth: entries |> Enum.map(&(&1["depth"] || 99)) |> Enum.min(),
        scopes: entries |> Enum.map(& &1["scope"]) |> Enum.reject(&is_nil/1) |> Enum.uniq(),
        direct: Enum.any?(entries, &(&1["depth"] == 1)),
        occurrences: length(entries)
      }
    end)
    |> Enum.sort_by(fn row ->
      {-row.module_count, -row.path_count, row.min_depth, row.coordinate}
    end)
  end

  @doc "Coordinates (`group:artifact:version`) for raw dependency entries."
  def coordinate(dep), do: "#{dep["group_id"]}:#{dep["artifact_id"]}:#{dep["version"]}"

  @doc "All introduction paths for one raw entry (v2 paths, legacy fallback)."
  def introduction_paths(dep) do
    case dep["introduction_paths"] do
      [_ | _] = paths -> paths
      _ -> [dep["introduced_via"] || []]
    end
  end

  @doc "Distinct module names across raw entries, sorted."
  def modules(dependencies) do
    dependencies
    |> Enum.map(& &1["module"])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Builds the introduction-path tree for one module as nested
  `{coordinate, children}` lists, roots first, children sorted.
  A nil module selects entries without module attribution (legacy).
  """
  def tree(dependencies, module) do
    dependencies
    |> Enum.filter(&(&1["module"] == module))
    |> Enum.flat_map(&introduction_paths/1)
    |> Enum.reject(&(&1 == []))
    |> Enum.uniq()
    |> Enum.reduce(%{}, fn path, acc -> insert_path(acc, path) end)
    |> to_sorted_list()
  end

  defp insert_path(tree, []), do: tree

  defp insert_path(tree, [head | rest]) do
    Map.update(tree, head, insert_path(%{}, rest), fn children ->
      insert_path(children, rest)
    end)
  end

  defp to_sorted_list(tree) do
    tree
    |> Enum.sort_by(fn {name, _children} -> name end)
    |> Enum.map(fn {name, children} -> {name, to_sorted_list(children)} end)
  end

  @doc "Counts every node in a tree built by `tree/2`."
  def tree_size(nodes) do
    Enum.reduce(nodes, 0, fn {_name, children}, acc -> acc + 1 + tree_size(children) end)
  end
end
