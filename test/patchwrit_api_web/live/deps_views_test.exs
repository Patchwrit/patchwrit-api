defmodule PatchwritApiWeb.DepsViewsTest do
  use PatchwritApiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias PatchwritApi.Analyses

  defp seed do
    {:ok, analysis} =
      Analyses.create_analysis(%{
        "repository_url" => "https://github.com/example/app",
        "requested_ref" => "main",
        "jdk_version" => "21",
        "resolved_sha" => "0123456789abcdef0123456789abcdef01234567",
        "worker_image" => "ghcr.io/patchwrit/patchwrit-worker@sha256:abc",
        "status" => "completed",
        "result" => %{
          "graph" => %{"complete" => true, "modules_total" => 1, "modules_resolved" => 1},
          "dependencies" => [
            %{
              "group_id" => "org.lib",
              "artifact_id" => "lib",
              "version" => "1.0",
              "scope" => "compile",
              "depth" => 1,
              "module" => "mod-a",
              "introduction_paths" => [["com.example:app:1.0", "org.lib:lib:1.0"]]
            },
            %{
              "group_id" => "org.hub",
              "artifact_id" => "hub",
              "version" => "2.0",
              "scope" => "compile",
              "depth" => 2,
              "module" => "mod-a",
              "introduction_paths" => [
                ["com.example:app:1.0", "org.lib:lib:1.0", "org.hub:hub:2.0"]
              ]
            }
          ]
        }
      })

    analysis
  end

  test "impact view ranks and direct view filters", %{conn: conn} do
    analysis = seed()
    {:ok, view, html} = live(conn, "/analyses/#{analysis.id}")

    assert html =~ "Dependencies (2 unique)"
    assert html =~ "org.hub:hub:2.0"

    view
    |> element("button[phx-click='set_deps_view'][phx-value-view='direct']")
    |> render_click()

    assert has_element?(view, ".pw-table td", "org.lib:lib:1.0")
    refute has_element?(view, ".pw-table td", "org.hub:hub:2.0")

    view
    |> element("button[phx-click='set_deps_view'][phx-value-view='all']")
    |> render_click()

    assert has_element?(view, ".pw-table td", "org.hub:hub:2.0")

    view
    |> form("form[phx-change='deps_search']", %{query: "hub"})
    |> render_change()

    assert has_element?(view, ".pw-table td", "org.hub:hub:2.0")
    refute has_element?(view, ".pw-table td", "org.lib:lib:1.0")
  end

  test "tree view renders introduction chains", %{conn: conn} do
    analysis = seed()
    {:ok, view, _html} = live(conn, "/analyses/#{analysis.id}")

    view
    |> element("button[phx-click='set_deps_view'][phx-value-view='tree']")
    |> render_click()

    assert has_element?(view, ".pw-tree", "com.example:app:1.0")
    assert has_element?(view, ".pw-tree", "org.hub:hub:2.0")
  end
end
