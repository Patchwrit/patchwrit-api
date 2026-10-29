defmodule PatchwritApiWeb.RepoPosture do
  @moduledoc """
  Latest known risk posture per tracked repository, shared by the
  docket and the repositories page.

  Posture always derives from the repository's latest analysis and
  persisted tribunal verdicts. A failed newer run never erases the
  last known posture, and no verdict is ever recalculated here.
  """

  alias PatchwritApi.Findings
  alias PatchwritApi.Tribunal

  @attention_recommendations ~w(remediate_now needs_human_review investigate_usage)
  @recommendation_rank %{
    "remediate_now" => 0,
    "needs_human_review" => 1,
    "investigate_usage" => 2,
    "schedule_remediation" => 3,
    "dismiss" => 4
  }

  @doc "Returns `%{repository_id => posture}` for every repository."
  def postures(repositories, analyses) do
    Map.new(repositories, fn repository ->
      case latest_analysis(analyses, repository) do
        nil ->
          {repository.id,
           %{
             latest: nil,
             findings: 0,
             attention: 0,
             worst: nil,
             coverage: "Not yet evaluated",
             evaluated: nil
           }}

        latest ->
          verdicts =
            latest.id
            |> Tribunal.latest_verdicts_for_analysis()
            |> Map.values()

          {repository.id,
           %{
             latest: latest,
             findings: Findings.count_findings_for_analysis(latest.id),
             attention: Enum.count(verdicts, &(&1.recommendation in @attention_recommendations)),
             worst: worst_recommendation(verdicts),
             coverage: graph_label(latest),
             evaluated: evaluated_label(latest)
           }}
      end
    end)
  end

  @doc "Human graph-coverage label for an analysis, unknown stated plainly."
  def graph_label(analysis) do
    graph = analysis.result && analysis.result["graph"]

    cond do
      is_map(graph) and graph["complete"] ->
        "Graph complete (#{graph["modules_resolved"]}/#{graph["modules_total"]} modules)"

      is_map(graph) ->
        "Graph partial (#{graph["modules_resolved"]}/#{graph["modules_total"]} modules)"

      analysis.status == "completed" ->
        "Graph completeness unknown"

      true ->
        "Not yet evaluated"
    end
  end

  @doc "When the latest posture was produced."
  def evaluated_label(analysis) do
    if analysis.osv_scanned_at do
      "Evaluated #{Calendar.strftime(analysis.osv_scanned_at, "%Y-%m-%d")}"
    else
      "Updated #{Calendar.strftime(analysis.updated_at, "%Y-%m-%d")}"
    end
  end

  defp latest_analysis(analyses, repository) do
    Enum.find(analyses, &(&1.repository_id == repository.id))
  end

  defp worst_recommendation([]), do: nil

  defp worst_recommendation(verdicts) do
    verdicts
    |> Enum.min_by(&Map.get(@recommendation_rank, &1.recommendation, 5))
    |> Map.get(:recommendation)
  end
end
