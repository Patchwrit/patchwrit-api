defmodule PatchwritApi.Findings do
  @moduledoc """
  Context for OSV findings derived from an analysis's dependencies.

  Findings are rebuilt wholesale by each scan: `record_scan/3` replaces
  the analysis's findings and stamps `analyses.osv_scanned_at` in one
  transaction, so readers never see a half-written scan.
  """

  import Ecto.Query, warn: false

  alias PatchwritApi.Analyses
  alias PatchwritApi.Analyses.Analysis
  alias PatchwritApi.Findings.Finding
  alias PatchwritApi.Repo

  def list_findings_for_analysis(analysis_id) do
    Finding
    |> where(analysis_id: ^analysis_id)
    |> order_by(asc: :package_name, asc: :osv_id)
    |> Repo.all()
  end

  def count_findings_for_analysis(analysis_id) do
    Repo.aggregate(from(f in Finding, where: f.analysis_id == ^analysis_id), :count)
  end

  @doc """
  Replaces the analysis's findings with `finding_attrs` and records the
  scan time. An empty list is a valid scan result (scanned, none found).
  """
  def record_scan(%Analysis{} = analysis, finding_attrs, scanned_at \\ DateTime.utc_now()) do
    Repo.transaction(fn ->
      Repo.delete_all(from(f in Finding, where: f.analysis_id == ^analysis.id))

      Enum.each(finding_attrs, fn attrs ->
        %Finding{}
        |> Finding.changeset(Map.put(attrs, "analysis_id", analysis.id))
        |> Repo.insert!()
      end)

      {:ok, updated} =
        Analyses.update_analysis(analysis, %{
          "osv_scanned_at" => DateTime.truncate(scanned_at, :second)
        })

      updated
    end)
  end
end
