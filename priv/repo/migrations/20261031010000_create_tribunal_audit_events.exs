defmodule PatchwritApi.Repo.Migrations.CreateTribunalAuditEvents do
  use Ecto.Migration

  def change do
    create table(:tribunal_audit_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # No foreign key on purpose: an audit event must survive the
      # case it describes. Rescans replace cases wholesale; the audit
      # trail (keyed also by snapshot hash in metadata) stays.
      add :tribunal_case_id, :binary_id, null: false

      add :analysis_id, references(:analyses, type: :binary_id, on_delete: :delete_all)

      add :event, :string, null: false
      add :actor, :string, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:tribunal_audit_events, [:tribunal_case_id, :inserted_at])
    create index(:tribunal_audit_events, [:analysis_id, :inserted_at])
    create index(:tribunal_audit_events, [:event])

    alter table(:tribunal_verdicts) do
      add :policy_version, :string
    end
  end
end
