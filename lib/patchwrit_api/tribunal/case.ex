defmodule PatchwritApi.Tribunal.Case do
  @moduledoc """
  One tribunal case: a single finding plus its evidence packet.

  T1 scope: `packet` holds the Investigator's deterministic,
  tool-observed facts (see `PatchwritApi.Tribunal.Investigator`).
  Agent opinions and the Judge's verdict are layered on in later
  milestones; nothing in the packet is model-generated.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(evidence_ready)

  schema "tribunal_cases" do
    belongs_to :analysis, PatchwritApi.Analyses.Analysis
    belongs_to :finding, PatchwritApi.Findings.Finding

    field :status, :string, default: "evidence_ready"
    field :packet, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(case_record, attrs) do
    case_record
    |> cast(attrs, [:analysis_id, :finding_id, :status, :packet])
    |> validate_required([:analysis_id, :finding_id, :packet])
    |> validate_inclusion(:status, @statuses)
    |> assoc_constraint(:analysis)
    |> assoc_constraint(:finding)
    |> unique_constraint(:finding_id)
  end
end
