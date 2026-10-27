defmodule PatchwritApi.Dispatch do
  @moduledoc """
  Provisions a worker Machine for one Analysis and waits for its callback.

  Run by the Oban dispatch worker. The callback (WorkerCallbackController)
  persists the result and performs cleanup; this module handles setup,
  timeout, and failure cleanup so no path strands a Machine.
  """

  alias PatchwritApi.Analyses
  alias PatchwritApi.Fly.Client

  @poll_ms 1_000

  def run(analysis_id) do
    analysis = Analyses.get_analysis!(analysis_id)

    cond do
      analysis.status in ~w(completed failed cancelled) ->
        :ok

      is_nil(callback_base_url()) ->
        fail(analysis, "internal", "CALLBACK_BASE_URL is not configured; refusing to dispatch")
        :ok

      true ->
        dispatch(analysis)
    end
  end

  defp dispatch(analysis) do
    with {:ok, analysis} <- Analyses.transition(analysis, "provisioning"),
         {:ok, sha} <- resolve_sha(analysis),
         {:ok, analysis} <- Analyses.update_analysis(analysis, %{"resolved_sha" => sha}),
         {:ok, token, analysis} <- issue_callback_token(analysis),
         {:ok, created} <- Client.create_worker_machine(worker_attrs(analysis, sha, token)),
         {:ok, analysis} <-
           Analyses.update_analysis(analysis, %{
             "machine_id" => created.data.id,
             "worker_image" => worker_image_label()
           }),
         {:ok, analysis} <- Analyses.transition(analysis, "running") do
      wait_for_callback(analysis)
    else
      {:error, :invalid_transition} -> :ok
      {:error, %{message: message}} -> fail_and_cleanup(analysis, message)
      {:error, message} when is_binary(message) -> fail_and_cleanup(analysis, message)
      {:error, _changeset} -> fail_and_cleanup(analysis, "failed to persist dispatch state")
    end
  end

  defp resolve_sha(analysis) do
    resolver = Application.get_env(:patchwrit_api, :sha_resolver, &PatchwritApi.Git.resolve_sha/2)
    resolver.(analysis.repository_url, analysis.requested_ref)
  end

  defp issue_callback_token(analysis) do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    hash = :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)

    case Analyses.update_analysis(analysis, %{"callback_token_hash" => hash}) do
      {:ok, updated} -> {:ok, token, updated}
      other -> other
    end
  end

  defp worker_attrs(analysis, sha, token) do
    %{
      "name" => "patchwrit-#{String.slice(analysis.id, 0, 8)}",
      "env" => %{
        "PATCHWRIT_JOB_ID" => analysis.id,
        "PATCHWRIT_REPOSITORY_URL" => analysis.repository_url,
        "PATCHWRIT_PINNED_SHA" => sha,
        "PATCHWRIT_CALLBACK_URL" =>
          "#{callback_base_url()}/api/v1/worker-callbacks/#{analysis.id}",
        "PATCHWRIT_CALLBACK_TOKEN" => token,
        "PATCHWRIT_TIMEOUT_SECONDS" => "300",
        "PATCHWRIT_JDK" => "auto",
        "PATCHWRIT_MAVEN" => "auto"
      }
    }
  end

  defp wait_for_callback(analysis) do
    deadline = System.monotonic_time(:second) + timeout_seconds()
    poll(analysis.id, deadline)
  end

  defp poll(id, deadline) do
    analysis = Analyses.get_analysis!(id)

    cond do
      analysis.status in ~w(completed failed cancelled) ->
        :ok

      System.monotonic_time(:second) > deadline ->
        fail_and_cleanup(analysis, "worker callback timed out")
        :ok

      true ->
        Process.sleep(@poll_ms)
        poll(id, deadline)
    end
  end

  @doc "Destroys the analysis Machine (if any) and records cleanup. Idempotent."
  def cleanup(analysis) do
    if analysis.machine_id do
      case Client.delete_machine(analysis.machine_id) do
        {:ok, _} -> Analyses.set_cleanup_status(analysis, "destroyed")
        {:error, _} -> Analyses.set_cleanup_status(analysis, "failed")
      end
    else
      Analyses.set_cleanup_status(analysis, "destroyed")
    end
  end

  defp fail_and_cleanup(analysis, message) do
    analysis = Analyses.get_analysis!(analysis.id)
    fail(analysis, "internal", message)
    cleanup(Analyses.get_analysis!(analysis.id))
    :ok
  end

  defp fail(analysis, category, message) do
    if analysis.status in ~w(completed failed cancelled) do
      {:ok, analysis}
    else
      analysis
      |> Analyses.update_analysis(%{"error_category" => category, "error_message" => message})
      |> case do
        {:ok, updated} -> Analyses.transition(updated, "failed")
        other -> other
      end
    end
  end

  defp callback_base_url, do: Application.get_env(:patchwrit_api, :callback_base_url)
  defp worker_image_label, do: Application.get_env(:patchwrit_api, :fly, [])[:worker_image]
  defp timeout_seconds, do: Application.get_env(:patchwrit_api, :dispatch_timeout_seconds, 180)
end
