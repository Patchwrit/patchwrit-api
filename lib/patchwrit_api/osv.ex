defmodule PatchwritApi.Osv do
  @moduledoc """
  Scans one completed analysis's persisted dependencies against OSV and
  records the resulting findings (see `PatchwritApi.Osv.Client` and
  `PatchwritApi.Findings`).
  """

  alias PatchwritApi.Analyses.Analysis
  alias PatchwritApi.Findings
  alias PatchwritApi.Osv.Client

  def scan_analysis(%Analysis{} = analysis) do
    dependencies = get_in(analysis.result || %{}, ["dependencies"]) || []

    case Client.scan_dependencies(dependencies) do
      {:ok, finding_attrs} -> Findings.record_scan(analysis, finding_attrs)
      {:error, message} -> {:error, message}
    end
  end
end
