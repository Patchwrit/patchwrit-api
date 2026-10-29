defmodule PatchwritApi.Repo.Migrations.AddNameToRepositories do
  use Ecto.Migration

  def up do
    alter table(:repositories) do
      add :name, :string
    end

    # Backfill from the stored URL: owner/repo without scheme, host,
    # trailing slash, or .git suffix.
    execute("""
    UPDATE repositories
    SET name = regexp_replace(
      regexp_replace(repository_url, '^https://github\\.com/', ''),
      '(\\.git|/)$', '')
    WHERE name IS NULL
    """)
  end

  def down do
    alter table(:repositories) do
      remove :name
    end
  end
end
