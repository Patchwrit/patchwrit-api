defmodule PatchwritApi.Tribunal.Triage do
  @moduledoc """
  Deterministic tribunal selection: which cases are worth model spend.

  A case is eligible when the finding's dependency is direct **or**
  compile/runtime scope, and a severity was reported. Selection order
  is stable — direct dependencies first, then package, then advisory —
  and the list is capped (10 per analysis by default) as the
  per-analysis spend guardrail. No model is consulted here.
  """

  alias PatchwritApi.Tribunal.Case

  @default_limit 10
  @eligible_scopes ~w(compile runtime)

  def default_limit, do: @default_limit

  @doc "Selects up to `limit` eligible cases in deterministic order."
  def select_cases(cases, limit \\ @default_limit) do
    cases
    |> Enum.filter(&eligible?/1)
    |> Enum.sort_by(&sort_key/1)
    |> Enum.take(limit)
  end

  @doc "Whether a case qualifies for tribunal spend under triage."
  def eligible?(%Case{} = case_record) do
    dossier = dossier_for(case_record)
    artifact = dossier["artifact"] || %{}
    advisories = dossier["advisories"] || []

    (artifact["direct"] == true or artifact["scope"] in @eligible_scopes) and
      Enum.any?(advisories, fn advisory ->
        is_binary(advisory["severity"]) and advisory["severity"] != ""
      end)
  end

  defp sort_key(%Case{} = case_record) do
    dossier = dossier_for(case_record)
    artifact = dossier["artifact"] || %{}
    advisory = List.first(dossier["advisories"] || []) || %{}

    {
      if(artifact["direct"] == true, do: 0, else: 1),
      "#{artifact["group_id"]}:#{artifact["artifact_id"]}",
      advisory["id"] || ""
    }
  end

  defp dossier_for(%Case{} = case_record) do
    case case_record.dossier_snapshot do
      snapshot when is_map(snapshot) and snapshot != %{} -> snapshot
      _ -> case_record.packet || %{}
    end
  end
end
