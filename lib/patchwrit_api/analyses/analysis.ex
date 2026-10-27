defmodule PatchwritApi.Analyses.Analysis do
  @moduledoc """
  A persisted vulnerability-analysis request (see docs/ANALYSIS_CONTRACT.md).

  `status` is the analysis lifecycle. `machine_cleanup_status` tracks Fly
  Machine disposal independently: a failed analysis can still have a
  successfully destroyed Machine, and vice versa.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(queued provisioning running completed failed cancelled)
  @cleanup_statuses ~w(pending destroyed failed)

  schema "analyses" do
    field :repository_url, :string
    field :requested_ref, :string, default: "HEAD"
    field :resolved_sha, :string
    field :status, :string, default: "queued"
    field :machine_id, :string
    field :machine_cleanup_status, :string, default: "pending"
    field :worker_image, :string
    field :runtime, :map, default: %{}
    field :callback_token_hash, :string
    field :result, :map
    field :error_category, :string
    field :error_message, :string
    field :timings, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses
  def cleanup_statuses, do: @cleanup_statuses

  def changeset(analysis, attrs) do
    analysis
    |> cast(attrs, [
      :repository_url,
      :requested_ref,
      :resolved_sha,
      :status,
      :machine_id,
      :machine_cleanup_status,
      :worker_image,
      :runtime,
      :callback_token_hash,
      :result,
      :error_category,
      :error_message,
      :timings
    ])
    |> validate_required([:repository_url])
    |> validate_github_url()
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:machine_cleanup_status, @cleanup_statuses)
  end

  defp validate_github_url(changeset) do
    validate_format(
      changeset,
      :repository_url,
      ~r{\Ahttps://github\.com/[\w.-]+/[\w.-]+(\.git)?/?\z},
      message: "must be a public GitHub repository URL"
    )
  end
end
