defmodule PatchwritApi.Findings.Finding do
  @moduledoc """
  One OSV vulnerability affecting one resolved dependency of an analysis.

  A finding is derived evidence: it is fully rebuilt on every scan, so a
  rescan replaces the analysis's findings rather than accumulating rows.
  `raw` keeps the complete OSV entry for later tribunal use.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "findings" do
    belongs_to :analysis, PatchwritApi.Analyses.Analysis

    field :osv_id, :string
    field :package_name, :string
    field :package_version, :string
    field :summary, :string
    field :severity, :string
    field :fixed_versions, {:array, :string}, default: []
    field :aliases, {:array, :string}, default: []
    field :raw, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  def changeset(finding, attrs) do
    finding
    |> cast(attrs, [
      :analysis_id,
      :osv_id,
      :package_name,
      :package_version,
      :summary,
      :severity,
      :fixed_versions,
      :aliases,
      :raw
    ])
    |> validate_required([:analysis_id, :osv_id, :package_name, :package_version])
    |> assoc_constraint(:analysis)
    |> unique_constraint([:analysis_id, :osv_id, :package_name, :package_version])
  end
end
