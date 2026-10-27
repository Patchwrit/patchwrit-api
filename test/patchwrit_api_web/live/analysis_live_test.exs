defmodule PatchwritApiWeb.AnalysisLiveTest do
  use PatchwritApiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias PatchwritApi.Analyses

  @repo "https://github.com/spring-petclinic/spring-framework-petclinic"

  test "renders the submit form and empty state", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/analyses")
    assert html =~ "Start an analysis"
    assert html =~ "No analyses yet"
    assert html =~ "/patchwrit.css"
    assert html =~ "pw-shell"
  end

  test "submitting a valid repository creates a queued analysis in the list", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/analyses")

    view
    |> form("#analysis-form", analysis: %{repository_url: @repo, requested_ref: "main"})
    |> render_submit()

    html = render(view)
    assert html =~ @repo
    assert html =~ "queued"
    assert html =~ "pending"
    assert [%{status: "queued", requested_ref: "main"}] = Analyses.list_analyses()
  end

  test "submitting an invalid repository shows an error and persists nothing", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/analyses")

    view
    |> form("#analysis-form", analysis: %{repository_url: "https://example.com/a/b"})
    |> render_submit()

    assert render(view) =~ "must be a public GitHub repository URL"
    assert Analyses.list_analyses() == []
  end

  test "detail page shows status and cleanup state", %{conn: conn} do
    {:ok, analysis} = Analyses.create_analysis(%{"repository_url" => @repo})

    {:ok, _view, html} = live(conn, "/analyses/#{analysis.id}")
    assert html =~ @repo
    assert html =~ "queued"
    assert html =~ "pending"
    assert html =~ analysis.id
  end
end
