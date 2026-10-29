defmodule PatchwritApi.Tribunal.PolicyGate do
  @moduledoc """
  Deterministic Phoenix policy applied to every Judge verdict.

  This is deliberately small and model-free. Its one rule in this
  milestone: when the dependency graph is incomplete or its
  completeness is unknown, the enforceable recommendation is capped
  at `needs_human_review` no matter what the Judge suggested.

  The cap records incomplete evidence — nothing more. It must never
  be read as low severity, non-use, or non-exploitability, and it
  grants no permission to automate a change.
  """

  @cap "needs_human_review"
  @note "dependency graph incomplete or unknown; recommendation capped at needs_human_review (incomplete evidence, not a safety finding)"

  @doc """
  Applies the gate to the Judge's recommendation for a dossier.
  Returns `%{recommendation, policy_capped, policy_notes}`.
  """
  def apply_gate(judge_recommendation, dossier) when is_map(dossier) do
    if graph_complete?(dossier) do
      %{recommendation: judge_recommendation, policy_capped: false, policy_notes: []}
    else
      %{
        recommendation: @cap,
        policy_capped: judge_recommendation != @cap,
        policy_notes: [@note]
      }
    end
  end

  @doc "Only an explicit graph block with `complete: true` proves completeness."
  def graph_complete?(dossier) do
    get_in(dossier, ["graph", "complete"]) == true
  end
end
