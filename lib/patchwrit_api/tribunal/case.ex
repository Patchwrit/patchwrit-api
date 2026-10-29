defmodule PatchwritApi.Tribunal.Case do
  @moduledoc """
  One tribunal case: a single finding plus its evidence dossier.

  `packet` is the current dossier view; `dossier_snapshot` is the
  immutable copy frozen when the dossier was built, identified by
  `dossier_version` and `snapshot_hash`. Tribunal opinions and
  verdicts must reference the snapshot, never the mutable view, so a
  later rebuild cannot change the evidence a verdict was based on.
  Nothing in either is model-generated.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(evidence_ready opinions_ready)

  schema "tribunal_cases" do
    belongs_to :analysis, PatchwritApi.Analyses.Analysis
    belongs_to :finding, PatchwritApi.Findings.Finding

    field :status, :string, default: "evidence_ready"
    field :packet, :map, default: %{}
    field :dossier_version, :integer, default: 1
    field :dossier_snapshot, :map, default: %{}
    field :snapshot_hash, :string

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(case_record, attrs) do
    case_record
    |> cast(attrs, [
      :analysis_id,
      :finding_id,
      :status,
      :packet,
      :dossier_version,
      :dossier_snapshot,
      :snapshot_hash
    ])
    |> validate_required([:analysis_id, :finding_id, :packet])
    |> validate_inclusion(:status, @statuses)
    |> assoc_constraint(:analysis)
    |> assoc_constraint(:finding)
    |> unique_constraint(:finding_id)
  end
end
