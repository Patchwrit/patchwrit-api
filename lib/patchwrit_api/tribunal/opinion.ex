defmodule PatchwritApi.Tribunal.Opinion do
  @moduledoc """
  One persisted advocate argument for a tribunal case.

  Opinions are arguments, not decisions. A `completed` opinion passed
  Phoenix validation: its JSON parsed and every citation names an
  evidence ID from the case's frozen dossier snapshot (`snapshot_hash`
  pins which snapshot). A `failed` opinion records the attempt and why
  it was rejected (provider error, malformed output, fabricated
  citation) so the tribunal's failures stay auditable.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @roles ~w(prosecutor defender)
  @statuses ~w(completed failed)

  schema "tribunal_opinions" do
    belongs_to :tribunal_case, PatchwritApi.Tribunal.Case

    field :role, :string
    field :model, :string
    field :prompt_version, :string
    field :snapshot_hash, :string
    field :status, :string
    field :summary, :string
    field :arguments, {:array, :map}, default: []
    field :uncertainties, {:array, :string}, default: []
    field :citations, {:array, :string}, default: []
    field :usage, :map, default: %{}
    field :raw_content, :string
    field :error, :string

    timestamps(type: :utc_datetime)
  end

  def roles, do: @roles
  def statuses, do: @statuses

  def changeset(opinion, attrs) do
    opinion
    |> cast(attrs, [
      :tribunal_case_id,
      :role,
      :model,
      :prompt_version,
      :snapshot_hash,
      :status,
      :summary,
      :arguments,
      :uncertainties,
      :citations,
      :usage,
      :raw_content,
      :error
    ])
    |> validate_required([
      :tribunal_case_id,
      :role,
      :model,
      :prompt_version,
      :snapshot_hash,
      :status
    ])
    |> validate_inclusion(:role, @roles)
    |> validate_inclusion(:status, @statuses)
    |> assoc_constraint(:tribunal_case)
  end
end
