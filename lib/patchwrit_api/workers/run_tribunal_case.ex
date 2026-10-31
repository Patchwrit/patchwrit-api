defmodule PatchwritApi.Workers.RunTribunalCase do
  @moduledoc """
  Oban worker: run one tribunal case end to end.

  Chain: Prosecutor -> Defender -> Judge (+ policy gate), all over the
  case's frozen dossier snapshot. The worker is resume-aware and
  idempotent: a completed verdict ends the job immediately, and
  completed opinions are reused rather than re-argued, so a retried
  or duplicated job never silently re-spends on finished stages.

  `max_attempts` is deliberately 1. Model calls cost money and every
  failure is already persisted as a failed opinion/verdict on the
  case; an automatic retry would multiply spend without new
  information. Re-enqueueing is a human decision.
  """

  use Oban.Worker, queue: :tribunal, max_attempts: 1

  alias PatchwritApi.Analyses.Analysis
  alias PatchwritApi.Log
  alias PatchwritApi.Tribunal
  alias PatchwritApi.Tribunal.Advocates
  alias PatchwritApi.Tribunal.Judge
  alias PatchwritApi.Tribunal.Opinion
  alias PatchwritApi.Tribunal.Triage
  alias PatchwritApi.Tribunal.Verdict

  def enqueue(case_record, source \\ "manual") do
    result =
      %{"case_id" => case_record.id}
      |> new()
      |> Oban.insert()

    case result do
      {:ok, job} ->
        Tribunal.record_audit_event(
          case_record,
          "tribunal_queued",
          if(source == "triage", do: "system", else: "operator"),
          Map.merge(PatchwritApi.Meta.Client.config_snapshot(), %{
            "source" => source,
            "job_id" => job.id
          })
        )

      _ ->
        :ok
    end

    result
  end

  @doc """
  Enqueues tribunal jobs for the analysis's triage-selected cases.
  Returns `{:ok, selected_cases}`.
  """
  def enqueue_for_analysis(%Analysis{} = analysis, opts \\ []) do
    limit = Keyword.get(opts, :limit, Triage.default_limit())

    selected =
      analysis.id
      |> Tribunal.list_cases_for_analysis()
      |> Triage.select_cases(limit)

    Enum.each(selected, &enqueue(&1, "triage"))

    Log.info("tribunal.enqueued", %{
      analysis_id: analysis.id,
      cases: length(selected),
      limit: limit
    })

    {:ok, selected}
  end

  @impl true
  def perform(%Oban.Job{args: %{"case_id" => case_id}}) do
    case Tribunal.get_case(case_id) do
      nil ->
        Log.warning("tribunal.cancelled", %{case_id: case_id, reason: "not_found"})

        Tribunal.record_audit_event(%{
          "tribunal_case_id" => case_id,
          "event" => "tribunal_cancelled",
          "actor" => "system",
          "metadata" => %{"reason" => "case_not_found"}
        })

        {:cancel, "case not found"}

      case_record ->
        run(case_record)
    end
  end

  # -- chain ------------------------------------------------------------------

  defp run(case_record) do
    if Tribunal.latest_completed_verdict(case_record.id) do
      Log.info("tribunal.skipped", %{case_id: case_record.id, reason: "verdict_exists"})

      Tribunal.record_audit_event(case_record, "tribunal_skipped", "system", %{
        "reason" => "verdict_exists"
      })

      :ok
    else
      started = System.monotonic_time(:millisecond)
      Log.info("tribunal.started", %{case_id: case_record.id})
      Tribunal.record_audit_event(case_record, "tribunal_started", "system", %{})

      with {:ok, prosecutor} <- advocate(case_record, "prosecutor", nil),
           {:ok, _defender} <- advocate(case_record, "defender", prosecutor),
           {:ok, verdict} <- Judge.run_verdict(case_record) do
        duration_ms = System.monotonic_time(:millisecond) - started

        Log.info("tribunal.completed", %{
          case_id: case_record.id,
          recommendation: verdict.recommendation,
          policy_capped: verdict.policy_capped,
          duration_ms: duration_ms
        })

        Tribunal.record_audit_event(case_record, "tribunal_completed", "system", %{
          "verdict_id" => verdict.id,
          "recommendation" => verdict.recommendation,
          "policy_capped" => verdict.policy_capped,
          "policy_version" => verdict.policy_version,
          "duration_ms" => duration_ms
        })

        :ok
      else
        {:error, %Opinion{role: role, error: error}} ->
          Log.warning("tribunal.failed", %{case_id: case_record.id, role: role, error: error})
          audit_failed(case_record, role, error, started)
          {:error, "#{role} opinion failed: #{error}"}

        {:error, %Verdict{error: error}} ->
          Log.warning("tribunal.failed", %{case_id: case_record.id, role: "judge", error: error})
          audit_failed(case_record, "judge", error, started)
          {:error, "judge verdict failed: #{error}"}

        {:error, message} ->
          Log.warning("tribunal.failed", %{case_id: case_record.id, error: message})
          audit_failed(case_record, "system", message, started)
          {:error, message}
      end
    end
  end

  defp audit_failed(case_record, stage, error, started) do
    Tribunal.record_audit_event(case_record, "tribunal_failed", "system", %{
      "stage" => stage,
      "error" => error,
      "duration_ms" => System.monotonic_time(:millisecond) - started
    })
  end

  # Reuse a completed opinion when one exists; otherwise argue it now.
  defp advocate(case_record, role, prosecutor) do
    case Tribunal.latest_completed_opinion(case_record.id, role) do
      nil ->
        case role do
          "prosecutor" -> Advocates.run_prosecutor(case_record)
          "defender" -> Advocates.run_defender(case_record, prosecutor)
        end

      opinion ->
        {:ok, opinion}
    end
  end
end
