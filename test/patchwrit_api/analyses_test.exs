defmodule PatchwritApi.AnalysesTest do
  use PatchwritApi.DataCase, async: true

  alias PatchwritApi.Analyses
  alias PatchwritApi.Analyses.Analysis

  @valid %{
    "repository_url" => "https://github.com/spring-petclinic/spring-framework-petclinic",
    "requested_ref" => "main"
  }

  test "create_analysis persists a queued analysis with defaults" do
    assert {:ok, %Analysis{} = analysis} = Analyses.create_analysis(@valid)
    assert analysis.status == "queued"
    assert analysis.machine_cleanup_status == "pending"
    assert analysis.requested_ref == "main"
    assert analysis.id
  end

  test "create_analysis defaults requested_ref and rejects non-GitHub URLs" do
    assert {:ok, analysis} =
             Analyses.create_analysis(%{
               "repository_url" => "https://github.com/ryanmcmorrowsnyk/vulnerable-java-app"
             })

    assert analysis.requested_ref == "HEAD"

    assert {:error, changeset} =
             Analyses.create_analysis(%{"repository_url" => "https://example.com/a/b"})

    assert "must be a public GitHub repository URL" in errors_on(changeset).repository_url
  end

  test "create_analysis requires a repository URL" do
    assert {:error, changeset} = Analyses.create_analysis(%{})
    assert "can't be blank" in errors_on(changeset).repository_url
  end

  test "status transitions follow the lifecycle and terminal states are final" do
    {:ok, analysis} = Analyses.create_analysis(@valid)

    assert {:ok, analysis} = Analyses.transition(analysis, "provisioning")
    assert {:ok, analysis} = Analyses.transition(analysis, "running")
    assert {:error, :invalid_transition} = Analyses.transition(analysis, "queued")
    assert {:ok, analysis} = Analyses.transition(analysis, "completed")
    assert {:error, :invalid_transition} = Analyses.transition(analysis, "running")
  end

  test "cleanup status is tracked independently of analysis status" do
    {:ok, analysis} = Analyses.create_analysis(@valid)
    assert {:ok, analysis} = Analyses.set_cleanup_status(analysis, "destroyed")
    assert analysis.machine_cleanup_status == "destroyed"
    assert analysis.status == "queued"
    assert {:error, :invalid_cleanup_status} = Analyses.set_cleanup_status(analysis, "running")
  end

  test "create_analysis_for_repository snapshots repository configuration" do
    {:ok, repository} =
      PatchwritApi.Repositories.create_repository(%{
        "repository_url" => "https://github.com/spring-petclinic/spring-framework-petclinic",
        "default_ref" => "javaconfig",
        "java_version" => "17"
      })

    assert {:ok, analysis} = Analyses.create_analysis_for_repository(repository)
    assert analysis.repository_id == repository.id
    assert analysis.repository_url == repository.repository_url
    assert analysis.requested_ref == "javaconfig"
    assert analysis.jdk_version == "17"
    assert analysis.runtime == %{"jdk" => "17"}

    {:ok, _repository} =
      PatchwritApi.Repositories.update_repository(repository, %{"java_version" => "21"})

    persisted = Analyses.get_analysis!(analysis.id)
    assert persisted.jdk_version == "17"
    assert persisted.runtime == %{"jdk" => "17"}
  end

  test "get and list return persisted analyses" do
    {:ok, analysis} = Analyses.create_analysis(@valid)
    assert Analyses.get_analysis!(analysis.id).id == analysis.id
    assert Enum.map(Analyses.list_analyses(), & &1.id) == [analysis.id]
  end
end
