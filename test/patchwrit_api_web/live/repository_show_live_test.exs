defmodule PatchwritApiWeb.RepositoryShowLiveTest do
  use PatchwritApiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias PatchwritApi.Analyses
  alias PatchwritApi.Repositories

  test "repository page shows config and its runs", %{conn: conn} do
    {:ok, repository} =
      Repositories.create_repository(%{
        "repository_url" => "https://github.com/example/app",
        "default_ref" => "main",
        "java_version" => "21"
      })

    {:ok, analysis} =
      Analyses.create_analysis(%{
        "repository_id" => repository.id,
        "repository_url" => "https://github.com/example/app",
        "requested_ref" => "main",
        "jdk_version" => "21",
        "resolved_sha" => "0123456789abcdef0123456789abcdef01234567",
        "worker_image" => "ghcr.io/patchwrit/patchwrit-worker@sha256:abc",
        "status" => "completed",
        "result" => %{"dependencies" => []}
      })

    {:ok, _view, html} = live(conn, "/repositories/#{repository.id}")
    assert html =~ "example/app"
    assert html =~ "JDK 21"
    assert html =~ "Analysis history"
    assert html =~ "0123456"
    assert html =~ "/analyses/#{analysis.id}"
    assert html =~ "run-repository-#{repository.id}"
  end

  test "repository with no runs shows the empty state", %{conn: conn} do
    {:ok, repository} =
      Repositories.create_repository(%{
        "repository_url" => "https://github.com/example/empty",
        "default_ref" => "main",
        "java_version" => "17"
      })

    {:ok, _view, html} = live(conn, "/repositories/#{repository.id}")
    assert html =~ "No runs yet"
    assert html =~ "example/empty"
  end
end
