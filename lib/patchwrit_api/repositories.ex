defmodule PatchwritApi.Repositories do
  @moduledoc "Context for user-tracked GitHub repositories."

  import Ecto.Query, warn: false

  alias PatchwritApi.Repo
  alias PatchwritApi.Repositories.Repository

  def list_repositories do
    Repository
    |> order_by(asc: :repository_url)
    |> Repo.all()
  end

  def get_repository!(id), do: Repo.get!(Repository, id)
  def get_repository(id), do: Repo.get(Repository, id)

  def create_repository(attrs \\ %{}) do
    %Repository{}
    |> Repository.changeset(attrs)
    |> Repo.insert()
  end

  def update_repository(%Repository{} = repository, attrs) do
    repository
    |> Repository.changeset(attrs)
    |> Repo.update()
  end

  def change_repository(%Repository{} = repository, attrs \\ %{}) do
    Repository.changeset(repository, attrs)
  end
end
