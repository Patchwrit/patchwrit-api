defmodule PatchwritApiWeb.AnalysisLiveTest do
  use PatchwritApiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias PatchwritApi.Analyses
  alias PatchwritApi.Repositories

  @stub PatchwritApi.GitHubStub
  @repo "https://github.com/spring-petclinic/spring-framework-petclinic"

  setup do
    Req.Test.set_req_test_to_shared()

    previous = Application.get_env(:patchwrit_api, :github)

    Application.put_env(:patchwrit_api, :github,
      base_url: "https://api.github.com",
      req_options: [plug: {Req.Test, @stub}]
    )

    on_exit(fn ->
      if previous,
        do: Application.put_env(:patchwrit_api, :github, previous),
        else: Application.delete_env(:patchwrit_api, :github)
    end)

    Req.Test.stub(@stub, fn conn ->
      case conn.request_path do
        "/repos/spring-petclinic/spring-framework-petclinic" ->
          Req.Test.json(conn, %{"default_branch" => "main"})

        "/repos/spring-petclinic/spring-framework-petclinic/branches" ->
          Req.Test.json(conn, [
            %{"name" => "main", "commit" => %{"sha" => "aaa"}},
            %{"name" => "javaconfig", "commit" => %{"sha" => "bbb"}}
          ])

        _ ->
          conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"message" => "Not Found"})
      end
    end)

    :ok
  end

  test "renders the tracked repository form and empty states", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/analyses")
    assert html =~ "Track a repository"
    assert html =~ "No tracked repositories yet"
    assert html =~ "No analyses yet"
    assert html =~ "/patchwrit.css"
    assert html =~ "pw-shell"
  end

  test "entering a repository URL fetches branches on the spot", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/analyses")

    view
    |> form("#repository-form", repository: %{repository_url: @repo})
    |> render_change()

    html = render(view)
    assert html =~ "javaconfig"
    assert html =~ "Branches loaded from GitHub"
  end

  test "tracking a repository and running it snapshots its configuration", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/analyses")

    view
    |> form("#repository-form",
      repository: %{repository_url: @repo, default_ref: "javaconfig", java_version: "17"}
    )
    |> render_submit()

    html = render(view)
    assert html =~ @repo
    assert html =~ "JDK 17"
    assert html =~ "javaconfig"

    assert [%{repository_url: @repo, default_ref: "javaconfig", java_version: "17"}] =
             Repositories.list_repositories()

    repository = hd(Repositories.list_repositories())

    view
    |> element("#run-repository-#{repository.id}")
    |> render_click()

    assert render(view) =~ "queued"

    assert [%{repository_id: repository_id, jdk_version: "17", requested_ref: "javaconfig"}] =
             Analyses.list_analyses()

    assert repository_id == repository.id
  end

  test "tracking an invalid repository shows an error and persists nothing", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/analyses")

    view
    |> form("#repository-form", repository: %{repository_url: "https://example.com/a/b"})
    |> render_submit()

    assert render(view) =~ "must be a public GitHub repository URL"
    assert Repositories.list_repositories() == []
  end

  test "detail page shows JDK, status, and cleanup state", %{conn: conn} do
    {:ok, repository} =
      Repositories.create_repository(%{
        "repository_url" => @repo,
        "default_ref" => "main",
        "java_version" => "21"
      })

    {:ok, analysis} = Analyses.create_analysis_for_repository(repository)

    {:ok, _view, html} = live(conn, "/analyses/#{analysis.id}")
    assert html =~ @repo
    assert html =~ "JDK 21"
    assert html =~ "queued"
    assert html =~ "pending"
    assert html =~ analysis.id
  end
end
