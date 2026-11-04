defmodule PatchwritApi.Analyses.DependencyGraphTest do
  use ExUnit.Case, async: true

  alias PatchwritApi.Analyses.DependencyGraph

  defp dep(group, artifact, version, opts) do
    %{
      "group_id" => group,
      "artifact_id" => artifact,
      "version" => version,
      "scope" => Keyword.get(opts, :scope, "compile"),
      "depth" => Keyword.get(opts, :depth, 2),
      "module" => Keyword.get(opts, :module, "mod-a"),
      "introduction_paths" => Keyword.get(opts, :paths, [])
    }
  end

  defp deps do
    [
      dep("com.example", "app", "1.0",
        depth: 0,
        paths: [["com.example:app:1.0"]]
      ),
      dep("org.hub", "hub", "2.0",
        depth: 2,
        module: "mod-a",
        paths: [["com.example:app:1.0", "org.lib:lib:1.0", "org.hub:hub:2.0"]]
      ),
      dep("org.hub", "hub", "2.0",
        depth: 3,
        module: "mod-b",
        paths: [
          ["com.example:app:1.0", "org.other:other:1.0", "org.hub:hub:2.0"],
          ["com.example:app:1.0", "org.lib:lib:1.0", "org.hub:hub:2.0"]
        ]
      ),
      dep("org.lib", "lib", "1.0",
        depth: 1,
        paths: [["com.example:app:1.0", "org.lib:lib:1.0"]]
      ),
      dep("org.leaf", "leaf", "3.0",
        depth: 4,
        module: "mod-b",
        paths: [
          ["com.example:app:1.0", "org.lib:lib:1.0", "org.hub:hub:2.0", "org.leaf:leaf:3.0"]
        ]
      )
    ]
  end

  test "aggregate ranks by module spread then path fan-in" do
    rows = DependencyGraph.aggregate(deps())
    hub = Enum.find(rows, &(&1.coordinate == "org.hub:hub:2.0"))

    assert hub.module_count == 2
    assert hub.path_count == 2
    assert hub.min_depth == 2
    assert hub.direct == false
    assert hub.occurrences == 2

    # The hub outranks even the root artifact: it spans more modules.
    assert Enum.at(rows, 0).coordinate == "org.hub:hub:2.0"

    lib = Enum.find(rows, &(&1.coordinate == "org.lib:lib:1.0"))
    assert lib.direct == true
    # Downstream reach: lib carries hub + leaf; hub carries leaf only.
    assert lib.downstream == 2
    assert hub.downstream == 1
  end

  test "tree rebuilds introduction chains per module" do
    tree = DependencyGraph.tree(deps(), "mod-b")
    assert [{"com.example:app:1.0", children}] = tree
    names = Enum.map(children, &elem(&1, 0))
    assert "org.lib:lib:1.0" in names
    assert "org.other:other:1.0" in names
    assert DependencyGraph.tree_size(tree) == 6
  end

  test "modules lists distinct sorted module names" do
    assert DependencyGraph.modules(deps()) == ["mod-a", "mod-b"]
  end
end
