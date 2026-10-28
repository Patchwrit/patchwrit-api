defmodule PatchwritApi.Workers.ScanAnalysis do
  @moduledoc "Oban worker: OSV-scan one completed Analysis's dependencies."

  use Oban.Worker, queue: :scans, max_attempts: 3

  alias PatchwritApi.Analyses
  alias PatchwritApi.Osv

  def enqueue(analysis) do
    %{"analysis_id" => analysis.id}
    |> new()
    |> Oban.insert()
  end

  @impl true
  def perform(%Oban.Job{args: %{"analysis_id" => analysis_id}}) do
    case Analyses.get_analysis(analysis_id) do
      nil -> {:cancel, "analysis not found"}
      %{status: "completed"} = analysis -> scan(analysis)
      analysis -> {:cancel, "analysis is #{analysis.status}, not completed"}
    end
  end

  defp scan(analysis) do
    case Osv.scan_analysis(analysis) do
      {:ok, analysis} ->
        # Chain: fresh findings get Investigator evidence packets.
        PatchwritApi.Workers.InvestigateAnalysis.enqueue(analysis)
        :ok

      {:error, message} ->
        {:error, message}
    end
  end
end
