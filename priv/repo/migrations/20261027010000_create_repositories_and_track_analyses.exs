defmodule PatchwritApi.Repo.Migrations.CreateRepositoriesAndTrackAnalyses do
  use Ecto.Migration

  def change do
    create table(:repositories, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :repository_url, :string, null: false
      add :default_ref, :string, null: false, default: "HEAD"
      add :java_version, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:repositories, [:repository_url])

    alter table(:analyses) do
      add :repository_id,
          references(:repositories, type: :binary_id, on_delete: :nilify_all)

      add :jdk_version, :string
    end

    create index(:analyses, [:repository_id])
  end
end
