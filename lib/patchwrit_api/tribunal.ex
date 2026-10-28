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

  def list_cases_for_analysis(analysis_id) do
    Case
    |> where(analysis_id: ^analysis_id)
    |> order_by(asc: :inserted_at)
    |> Repo.all()
  end

  def count_cases_for_analysis(analysis_id) do
    Repo.aggregate(from(c in Case, where: c.analysis_id == ^analysis_id), :count)
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
