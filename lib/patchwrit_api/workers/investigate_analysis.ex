defmodule PatchwritApi.Workers.InvestigateAnalysis do
  @moduledoc "Oban worker: build Investigator evidence packets for one Analysis."

  use Oban.Worker, queue: :tribunal, max_attempts: 3

  alias PatchwritApi.Analyses
  alias PatchwritApi.Log
  alias PatchwritApi.Tribunal.Investigator

  def enqueue(analysis) do
    Log.info("investigate.enqueued", %{analysis_id: analysis.id})

    %{"analysis_id" => analysis.id}
    |> new()
    |> Oban.insert()
  end

  @impl true
  def perform(%Oban.Job{args: %{"analysis_id" => analysis_id}}) do
    case Analyses.get_analysis(analysis_id) do
      nil ->
        Log.warning("investigate.cancelled", %{analysis_id: analysis_id, reason: "not_found"})
        {:cancel, "analysis not found"}

      analysis ->
        started = System.monotonic_time(:millisecond)
        Log.info("investigate.started", %{analysis_id: analysis.id})
        {:ok, cases} = Investigator.investigate_analysis(analysis)
        duration_ms = System.monotonic_time(:millisecond) - started

        Analyses.merge_timings(analysis, %{
          "investigate_ms" => duration_ms,
          "cases" => length(cases)
        })

        Log.info("investigate.completed", %{
          analysis_id: analysis.id,
          cases: length(cases),
          duration_ms: duration_ms
        })

        :ok
    end
  end
end
