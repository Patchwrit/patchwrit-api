defmodule PatchwritApi.Repo.Migrations.AddDossierSnapshotToTribunalCases do
  use Ecto.Migration

  def change do
    alter table(:tribunal_cases) do
      add :dossier_version, :integer, null: false, default: 1
      add :dossier_snapshot, :map, null: false, default: %{}
      add :snapshot_hash, :string
    end
  end
end
