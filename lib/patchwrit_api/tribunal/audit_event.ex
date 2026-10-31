defmodule PatchwritApi.Tribunal.AuditEvent do
  @moduledoc """
  One entry in a tribunal case's append-only audit trail.

  Audit events are the governance record: what happened, who or what
  did it (system, operator, a model role, the policy gate), under
  which model/prompt/policy versions, and at what token cost. They
  carry small queryable facts and identifiers only — the evidence
  itself lives in the case's frozen dossier snapshot, and model
  outputs in the opinion/verdict rows each event points to.

  Events are never updated or deleted by application code, and they
  survive case replacement on rescan (no foreign key to cases).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @events ~w(
    case_created
    tribunal_queued tribunal_started tribunal_skipped tribunal_cancelled
    tribunal_completed tribunal_failed
    opinion_completed opinion_failed
    verdict_completed verdict_failed
    policy_applied
    verdict_group_applied graph_reused
  )

  @actors ~w(system operator investigator prosecutor defender judge policy_gate)

  def events, do: @events
  def actors, do: @actors

  schema "tribunal_audit_events" do
    field :tribunal_case_id, :binary_id
    field :analysis_id, :binary_id
    field :event, :string
    field :actor, :string
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:tribunal_case_id, :analysis_id, :event, :actor, :metadata])
    |> validate_required([:tribunal_case_id, :event, :actor])
    |> validate_inclusion(:event, @events)
    |> validate_inclusion(:actor, @actors)
  end
end
