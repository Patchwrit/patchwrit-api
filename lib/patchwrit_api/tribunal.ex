defmodule PatchwritApi.Tribunal do
  @moduledoc """
  Context for tribunal cases.

  Cases are derived evidence, rebuilt wholesale per investigation like
  findings are per scan: readers never see a half-rebuilt case set.
  """

  import Ecto.Query, warn: false

  alias PatchwritApi.Analyses.Analysis
  alias PatchwritApi.Repo
  alias PatchwritApi.Tribunal.Case
  alias PatchwritApi.Tribunal.Opinion
  alias PatchwritApi.Tribunal.Verdict

  def list_cases_for_analysis(analysis_id) do
    Case
    |> where(analysis_id: ^analysis_id)
    |> order_by(asc: :inserted_at)
    |> Repo.all()
  end

  def count_cases_for_analysis(analysis_id) do
    Repo.aggregate(from(c in Case, where: c.analysis_id == ^analysis_id), :count)
  end

  def get_case(id), do: Repo.get(Case, id)

  def update_case_status(%Case{} = case_record, status) do
    case_record
    |> Case.changeset(%{"status" => status})
    |> Repo.update()
  end

  @doc "Persists one advocate opinion (completed or failed) for a case."
  def create_opinion(attrs) do
    %Opinion{}
    |> Opinion.changeset(attrs)
    |> Repo.insert()
  end

  def list_opinions_for_case(tribunal_case_id) do
    Opinion
    |> where(tribunal_case_id: ^tribunal_case_id)
    |> order_by(asc: :inserted_at)
    |> Repo.all()
  end

  @doc "Latest completed opinion for a case + role, if one exists."
  def latest_completed_opinion(tribunal_case_id, role) do
    Opinion
    |> where(tribunal_case_id: ^tribunal_case_id, role: ^role, status: "completed")
    |> order_by(desc: :inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc "Latest completed verdict for a case, if one exists."
  def latest_completed_verdict(tribunal_case_id) do
    Verdict
    |> where(tribunal_case_id: ^tribunal_case_id, status: "completed")
    |> order_by(desc: :inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc "Persists one Judge verdict (completed or failed) for a case."
  def create_verdict(attrs) do
    %Verdict{}
    |> Verdict.changeset(attrs)
    |> Repo.insert()
  end

  def list_verdicts_for_case(tribunal_case_id) do
    Verdict
    |> where(tribunal_case_id: ^tribunal_case_id)
    |> order_by(asc: :inserted_at)
    |> Repo.all()
  end

  @doc "Latest completed verdict per case for one analysis, as `%{case_id => verdict}`."
  def latest_verdicts_for_analysis(analysis_id) do
    Verdict
    |> join(:inner, [v], c in Case, on: v.tribunal_case_id == c.id)
    |> where([v, c], c.analysis_id == ^analysis_id and v.status == "completed")
    |> order_by([v], desc: v.inserted_at)
    |> Repo.all()
    |> Enum.uniq_by(& &1.tribunal_case_id)
    |> Map.new(&{&1.tribunal_case_id, &1})
  end

  @attention_recommendations ~w(remediate_now needs_human_review investigate_usage)
  @priority_rank %{"critical" => 0, "high" => 1, "medium" => 2, "low" => 3, "unknown" => 4}

  @doc """
  Cases needing attention across all analyses: the latest completed
  verdict per case whose (policy-gated) recommendation is actionable,
  worst first — remediate now, policy-capped human review, other human
  review, then investigate usage; priority breaks ties inside groups.
  Verdicts come back with `tribunal_case` (plus finding and analysis)
  preloaded.
  """
  def attention_queue(limit \\ 20) do
    Verdict
    |> where(status: "completed")
    |> order_by(desc: :inserted_at)
    |> Repo.all()
    |> Enum.uniq_by(& &1.tribunal_case_id)
    |> Enum.filter(&(&1.recommendation in @attention_recommendations))
    |> Enum.sort_by(fn verdict ->
      {attention_rank(verdict), Map.get(@priority_rank, verdict.priority, 4)}
    end)
    |> Enum.take(limit)
    |> Repo.preload(tribunal_case: [:finding, :analysis])
  end

  @doc "Total measured model tokens across completed opinions and verdicts."
  def total_tokens do
    opinion_tokens =
      Opinion
      |> where(status: "completed")
      |> Repo.all()
      |> Enum.sum_by(&(&1.usage["total_tokens"] || 0))

    verdict_tokens =
      Verdict
      |> where(status: "completed")
      |> Repo.all()
      |> Enum.sum_by(&(&1.usage["total_tokens"] || 0))

    opinion_tokens + verdict_tokens
  end

  @doc "How many latest completed verdicts were policy-capped."
  def policy_capped_count do
    Verdict
    |> where(status: "completed")
    |> order_by(desc: :inserted_at)
    |> Repo.all()
    |> Enum.uniq_by(& &1.tribunal_case_id)
    |> Enum.count(& &1.policy_capped)
  end

  @doc "Counts of latest completed verdicts per final recommendation."
  def verdict_recommendation_counts do
    Verdict
    |> where(status: "completed")
    |> order_by(desc: :inserted_at)
    |> Repo.all()
    |> Enum.uniq_by(& &1.tribunal_case_id)
    |> Enum.frequencies_by(& &1.recommendation)
  end

  defp attention_rank(%Verdict{recommendation: "remediate_now"}), do: 0
  defp attention_rank(%Verdict{recommendation: "needs_human_review", policy_capped: true}), do: 1
  defp attention_rank(%Verdict{recommendation: "needs_human_review"}), do: 2
  defp attention_rank(%Verdict{recommendation: "investigate_usage"}), do: 3
  defp attention_rank(_verdict), do: 4

  @doc "Replaces the analysis's cases with `case_attrs` in one transaction."
  def replace_cases(%Analysis{} = analysis, case_attrs) do
    Repo.transaction(fn ->
      Repo.delete_all(from(c in Case, where: c.analysis_id == ^analysis.id))

      Enum.map(case_attrs, fn attrs ->
        %Case{}
        |> Case.changeset(attrs)
        |> Repo.insert!()
      end)
    end)
  end
end
