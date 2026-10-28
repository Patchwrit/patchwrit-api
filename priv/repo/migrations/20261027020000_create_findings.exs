defmodule PatchwritApi.Repo.Migrations.CreateFindings do
  use Ecto.Migration

  def change do
    alter table(:analyses) do
      add :osv_scanned_at, :utc_datetime
    end

    create table(:findings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :analysis_id,
          references(:analyses, type: :binary_id, on_delete: :delete_all),
          null: false

      add :osv_id, :string, null: false
      add :package_name, :string, null: false
      add :package_version, :string, null: false
      add :summary, :text
      add :severity, :string
      add :fixed_versions, {:array, :string}, null: false, default: []
      add :aliases, {:array, :string}, null: false, default: []
      add :raw, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:findings, [:analysis_id, :osv_id, :package_name, :package_version])
    create index(:findings, [:analysis_id])
  end
end
