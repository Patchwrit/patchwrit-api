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

  def update_analysis(%Analysis{} = analysis, attrs) do
    analysis
    |> Analysis.changeset(attrs)
    |> Repo.update()
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
