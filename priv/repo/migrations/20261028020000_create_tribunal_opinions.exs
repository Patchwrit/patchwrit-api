defmodule PatchwritApi.Repo.Migrations.CreateTribunalOpinions do
  use Ecto.Migration

  def change do
    create table(:tribunal_opinions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :tribunal_case_id,
          references(:tribunal_cases, type: :binary_id, on_delete: :delete_all),
          null: false

      add :role, :string, null: false
      add :model, :string, null: false
      add :prompt_version, :string, null: false
      add :snapshot_hash, :string, null: false
      add :status, :string, null: false
      add :summary, :text
      add :arguments, {:array, :map}, null: false, default: []
      add :uncertainties, {:array, :string}, null: false, default: []
      add :citations, {:array, :string}, null: false, default: []
      add :usage, :map, null: false, default: %{}
      add :raw_content, :text
      add :error, :text

      timestamps(type: :utc_datetime)
    end

    create index(:tribunal_opinions, [:tribunal_case_id])
    create index(:tribunal_opinions, [:snapshot_hash])
  end
end
