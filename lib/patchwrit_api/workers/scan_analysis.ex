defmodule PatchwritApi.Workers.ScanAnalysis do
  @moduledoc "Oban worker: OSV-scan one completed Analysis's dependencies."

  use Oban.Worker, queue: :scans, max_attempts: 3

  alias PatchwritApi.Analyses
  alias PatchwritApi.Log
  alias PatchwritApi.Osv

  def enqueue(analysis) do
    Log.info("scan.enqueued", %{analysis_id: analysis.id})

    %{"analysis_id" => analysis.id}
    |> new()
    |> Oban.insert()
  end

  @impl true
  def perform(%Oban.Job{args: %{"analysis_id" => analysis_id}}) do
    case Analyses.get_analysis(analysis_id) do
      nil ->
        Log.warning("scan.cancelled", %{analysis_id: analysis_id, reason: "not_found"})
        {:cancel, "analysis not found"}

      %{status: "completed"} = analysis ->
        scan(analysis)

      analysis ->
        Log.warning("scan.cancelled", %{
          analysis_id: analysis_id,
          reason: "not_completed",
          status: analysis.status
        })

        {:cancel, "analysis is #{analysis.status}, not completed"}
    end
  end

  defp scan(analysis) do
    started = System.monotonic_time(:millisecond)
    Log.info("scan.started", %{analysis_id: analysis.id})

    case Osv.scan_analysis(analysis) do
      {:ok, analysis} ->
        duration_ms = System.monotonic_time(:millisecond) - started
        findings = PatchwritApi.Findings.count_findings_for_analysis(analysis.id)

        Analyses.merge_timings(analysis, %{
          "scan_ms" => duration_ms,
          "findings" => findings
        })

        Log.info("scan.completed", %{
          analysis_id: analysis.id,
          findings: findings,
          duration_ms: duration_ms
        })

        # Chain: fresh findings get Investigator evidence packets.
        PatchwritApi.Workers.InvestigateAnalysis.enqueue(analysis)
        :ok

      {:error, message} ->
        Log.error("scan.failed", %{analysis_id: analysis.id, error: message})
        {:error, message}
    end
  end
end
