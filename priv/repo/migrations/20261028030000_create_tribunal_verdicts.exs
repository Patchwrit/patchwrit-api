defmodule PatchwritApi.Repo.Migrations.CreateTribunalVerdicts do
  use Ecto.Migration

  def change do
    create table(:tribunal_verdicts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :tribunal_case_id,
          references(:tribunal_cases, type: :binary_id, on_delete: :delete_all),
          null: false

      add :model, :string, null: false
      add :prompt_version, :string, null: false
      add :snapshot_hash, :string, null: false
      add :status, :string, null: false
      add :presence, :string
      add :application_relevance, :string
      add :exploitability, :string
      add :priority, :string
      add :judge_recommendation, :string
      add :recommendation, :string
      add :supporting_evidence_ids, {:array, :string}, null: false, default: []
      add :counter_evidence_ids, {:array, :string}, null: false, default: []
      add :missing_context, {:array, :string}, null: false, default: []
      add :rationale, :text
      add :policy_capped, :boolean, null: false, default: false
      add :policy_notes, {:array, :string}, null: false, default: []
      add :usage, :map, null: false, default: %{}
      add :raw_content, :text
      add :error, :text

      timestamps(type: :utc_datetime)
    end

    create index(:tribunal_verdicts, [:tribunal_case_id])
    create index(:tribunal_verdicts, [:snapshot_hash])
  end
end
