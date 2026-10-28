defmodule PatchwritApi.Workers.InvestigateAnalysis do
  @moduledoc "Oban worker: build Investigator evidence packets for one Analysis."

  use Oban.Worker, queue: :tribunal, max_attempts: 3

  alias PatchwritApi.Analyses
  alias PatchwritApi.Tribunal.Investigator

  def enqueue(analysis) do
    %{"analysis_id" => analysis.id}
    |> new()
    |> Oban.insert()
  end

  @impl true
  def perform(%Oban.Job{args: %{"analysis_id" => analysis_id}}) do
    case Analyses.get_analysis(analysis_id) do
      nil ->
        {:cancel, "analysis not found"}

      analysis ->
        {:ok, _cases} = Investigator.investigate_analysis(analysis)
        :ok
    end
  end
end
