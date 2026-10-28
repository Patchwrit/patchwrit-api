defmodule PatchwritApi.Analyses do
  @moduledoc """
  Context for persisted analyses (docs/ANALYSIS_CONTRACT.md).

  Owns creation and lifecycle transitions. Fly provisioning, Oban
  dispatch, and worker callbacks build on these functions in later
  milestones; nothing here talks to Fly.
  """

  import Ecto.Query, warn: false

  alias PatchwritApi.Analyses.Analysis
  alias PatchwritApi.Repo

  @transitions %{
    "queued" => ~w(provisioning cancelled failed),
    "provisioning" => ~w(running cancelled failed),
    "running" => ~w(completed cancelled failed),
    "completed" => [],
    "failed" => [],
    "cancelled" => []
  }

  def list_analyses do
    Analysis
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  def get_analysis!(id), do: Repo.get!(Analysis, id)
  def get_analysis(id), do: Repo.get(Analysis, id)

  def create_analysis(attrs \\ %{}) do
    %Analysis{}
    |> Analysis.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates an immutable run snapshot from a tracked repository.

  The repository's current URL, default ref, and Java version are copied;
  later edits to the tracked repository do not alter this analysis.
  """
  def create_analysis_for_repository(%PatchwritApi.Repositories.Repository{} = repository) do
    create_analysis(%{
      "repository_id" => repository.id,
      "repository_url" => repository.repository_url,
      "requested_ref" => repository.default_ref,
      "jdk_version" => repository.java_version,
      "runtime" => %{"jdk" => repository.java_version}
    })
  end

  def update_analysis(%Analysis{} = analysis, attrs) do
    analysis
    |> Analysis.changeset(attrs)
    |> Repo.update()
  end

  @doc "Merges stage instrumentation (durations/counts) into timings."
  def merge_timings(%Analysis{} = analysis, values) do
    update_analysis(analysis, %{"timings" => Map.merge(analysis.timings || %{}, values)})
  end

  @doc """
  Moves an analysis along its lifecycle. Terminal states accept no
  further transitions, so a late callback can never resurrect one.
  """
  def transition(%Analysis{} = analysis, to) do
    if to in Map.get(@transitions, analysis.status, []) do
      update_analysis(analysis, %{"status" => to})
    else
      {:error, :invalid_transition}
    end
  end

  @doc "Sets Machine cleanup state, independent of the analysis lifecycle."
  def set_cleanup_status(%Analysis{} = analysis, status) do
    if status in Analysis.cleanup_statuses() do
      update_analysis(analysis, %{"machine_cleanup_status" => status})
    else
      {:error, :invalid_cleanup_status}
    end
  end
end
