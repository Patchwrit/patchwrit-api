defmodule PatchwritApi.Tribunal.Verdict do
  @moduledoc """
  One Judge verdict for a tribunal case, after the policy gate.

  `judge_recommendation` is exactly what the Judge model returned;
  `recommendation` is what Phoenix enforces after the deterministic
  policy gate. When the gate caps a verdict, `policy_capped` is true
  and `policy_notes` say why — the cap is visible, never silent, and
  it records incomplete evidence only, never low severity or safety.

  Verdict dimensions are deliberately split: `presence`,
  `application_relevance`, and `exploitability` are separate claims,
  and `recommendation` never authorizes a code change in this
  milestone. A `failed` verdict records the rejected attempt.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(completed failed)
  @presence ~w(confirmed reported unknown)
  @relevance ~w(high medium low unknown)
  @exploitability ~w(proven plausible unlikely unknown)
  @priority ~w(critical high medium low unknown)
  @recommendations ~w(remediate_now schedule_remediation investigate_usage needs_human_review dismiss)

  schema "tribunal_verdicts" do
    belongs_to :tribunal_case, PatchwritApi.Tribunal.Case

    field :model, :string
    field :prompt_version, :string
    field :snapshot_hash, :string
    field :status, :string
    field :presence, :string
    field :application_relevance, :string
    field :exploitability, :string
    field :priority, :string
    field :judge_recommendation, :string
    field :recommendation, :string
    field :supporting_evidence_ids, {:array, :string}, default: []
    field :counter_evidence_ids, {:array, :string}, default: []
    field :missing_context, {:array, :string}, default: []
    field :rationale, :string
    field :policy_capped, :boolean, default: false
    field :policy_notes, {:array, :string}, default: []
    field :policy_version, :string
    field :usage, :map, default: %{}
    field :raw_content, :string
    field :error, :string

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses
  def presence_values, do: @presence
  def relevance_values, do: @relevance
  def exploitability_values, do: @exploitability
  def priority_values, do: @priority
  def recommendation_values, do: @recommendations

  def changeset(verdict, attrs) do
    verdict
    |> cast(attrs, [
      :tribunal_case_id,
      :model,
      :prompt_version,
      :snapshot_hash,
      :status,
      :presence,
      :application_relevance,
      :exploitability,
      :priority,
      :judge_recommendation,
      :recommendation,
      :supporting_evidence_ids,
      :counter_evidence_ids,
      :missing_context,
      :rationale,
      :policy_capped,
      :policy_notes,
      :policy_version,
      :usage,
      :raw_content,
      :error
    ])
    |> validate_required([:tribunal_case_id, :model, :prompt_version, :snapshot_hash, :status])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:presence, @presence)
    |> validate_inclusion(:application_relevance, @relevance)
    |> validate_inclusion(:exploitability, @exploitability)
    |> validate_inclusion(:priority, @priority)
    |> validate_inclusion(:judge_recommendation, @recommendations)
    |> validate_inclusion(:recommendation, @recommendations)
    |> assoc_constraint(:tribunal_case)
  end
end
