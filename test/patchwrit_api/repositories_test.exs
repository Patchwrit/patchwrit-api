defmodule PatchwritApi.RepositoriesTest do
  use PatchwritApi.DataCase, async: true

  alias PatchwritApi.Repositories
  alias PatchwritApi.Repositories.Repository

  @valid %{
    "repository_url" => "https://github.com/spring-petclinic/spring-framework-petclinic.git/",
    "default_ref" => "main",
    "java_version" => "17"
  }

  test "create_repository normalizes and persists a tracked repository" do
    assert {:ok, %Repository{} = repository} = Repositories.create_repository(@valid)

    assert repository.repository_url ==
             "https://github.com/spring-petclinic/spring-framework-petclinic"

    assert repository.default_ref == "main"
    assert repository.java_version == "17"
  end

  test "create_repository prevents duplicate tracked URLs" do
    assert {:ok, _repository} = Repositories.create_repository(@valid)

    assert {:error, changeset} =
             Repositories.create_repository(%{
               @valid
               | "repository_url" =>
                   "https://github.com/spring-petclinic/spring-framework-petclinic"
             })

    assert "has already been taken" in errors_on(changeset).repository_url
  end

  test "create_repository only accepts supported Java versions" do
    assert {:error, changeset} =
             Repositories.create_repository(%{@valid | "java_version" => "11"})

    assert "is invalid" in errors_on(changeset).java_version
  end

  test "list_repositories returns tracked repositories" do
    assert {:ok, repository} = Repositories.create_repository(@valid)
    assert Enum.map(Repositories.list_repositories(), & &1.id) == [repository.id]
  end
end
