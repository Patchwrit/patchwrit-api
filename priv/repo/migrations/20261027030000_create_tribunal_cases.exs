defmodule PatchwritApi.Repo.Migrations.CreateTribunalCases do
  use Ecto.Migration

  def change do
    create table(:tribunal_cases, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :analysis_id,
          references(:analyses, type: :binary_id, on_delete: :delete_all),
          null: false

      add :finding_id,
          references(:findings, type: :binary_id, on_delete: :delete_all),
          null: false

      add :status, :string, null: false, default: "evidence_ready"
      add :packet, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tribunal_cases, [:finding_id])
    create index(:tribunal_cases, [:analysis_id])
  end
end
