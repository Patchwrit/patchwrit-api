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
