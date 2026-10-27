defmodule PatchwritApi.Repo.Migrations.CreateAnalyses do
  use Ecto.Migration

  def change do
    create table(:analyses, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :repository_url, :string, null: false
      add :requested_ref, :string, null: false, default: "HEAD"
      add :resolved_sha, :string
      add :status, :string, null: false, default: "queued"
      add :machine_id, :string
      add :machine_cleanup_status, :string, null: false, default: "pending"
      add :worker_image, :string
      add :runtime, :map, null: false, default: %{}
      add :callback_token_hash, :string
      add :result, :map
      add :error_category, :string
      add :error_message, :string
      add :timings, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:analyses, [:status])
    create index(:analyses, [:machine_id])
  end
end
