defmodule PatchwritApiWeb.WorkerCallbackController do
  @moduledoc """
  Receives the worker's bounded result callback.

  Auth: the job-scoped bearer token issued at dispatch; only its hash is
  stored. Idempotent: the first terminal result wins, duplicates are
  acknowledged without changing the record. Cleanup runs here so a
  completed callback destroys its Machine immediately.
  """

  use PatchwritApiWeb, :controller

  alias PatchwritApi.Analyses
  alias PatchwritApi.Dispatch

  @max_payload_bytes 256 * 1024

  def create(conn, %{"id" => id} = params) do
    analysis = Analyses.get_analysis(id)

    cond do
      is_nil(analysis) ->
        render_error(conn, 404, "analysis not found")

      not authorized?(conn, analysis) ->
        render_error(conn, 401, "unauthorized")

      analysis.status in ~w(completed failed cancelled) ->
        json(conn, %{status: "already_recorded"})

      not valid_payload?(params) ->
        render_error(conn, 422, "invalid worker payload")

      true ->
        persist_and_cleanup(conn, analysis, params)
    end
  end

  defp persist_and_cleanup(conn, analysis, params) do
    result =
      Map.take(
        params,
        ~w(schema_version job_id status worker_version environment repository dependencies timings_ms errors)
      )

    attrs =
      case params["status"] do
        "failed" ->
          first = List.first(params["errors"] || []) || %{}

          %{
            "result" => result,
            "error_category" => first["category"] || "internal",
            "error_message" => first["message"] || "worker failed"
          }

        _ ->
          %{"result" => result}
      end

    with {:ok, analysis} <- Analyses.update_analysis(analysis, attrs),
         {:ok, analysis} <- Analyses.transition(analysis, terminal_status(params["status"])) do
      Dispatch.cleanup(analysis)
      maybe_enqueue_scan(analysis, params)
      json(conn, %{status: "recorded"})
    else
      _ -> render_error(conn, 422, "could not record result")
    end
  end

  # Only a completed run with a dependency graph is worth an OSV scan.
  defp maybe_enqueue_scan(analysis, %{"status" => "completed", "dependencies" => [_ | _]}) do
    PatchwritApi.Workers.ScanAnalysis.enqueue(analysis)
  end

  defp maybe_enqueue_scan(_analysis, _params), do: :ok

  defp terminal_status("failed"), do: "failed"
  defp terminal_status(_), do: "completed"

  defp authorized?(conn, analysis) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         hash when is_binary(hash) <- analysis.callback_token_hash do
      presented = :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
      Plug.Crypto.secure_compare(presented, hash)
    else
      _ -> false
    end
  end

  defp valid_payload?(params) do
    params["schema_version"] == 1 and params["status"] in ~w(completed failed) and
      byte_size(Jason.encode!(params)) <= @max_payload_bytes
  end

  defp render_error(conn, status, message) do
    conn
    |> put_status(status)
    |> json(%{error: %{status: status, message: message}})
  end
end
