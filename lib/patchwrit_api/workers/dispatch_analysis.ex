defmodule PatchwritApi.Workers.DispatchAnalysis do
  @moduledoc "Oban worker: dispatch one Analysis to a Fly worker Machine."

  use Oban.Worker, queue: :dispatch, max_attempts: 1

  alias PatchwritApi.Dispatch
  alias PatchwritApi.Log

  def enqueue(analysis) do
    Log.info("dispatch.enqueued", %{analysis_id: analysis.id})

    %{"analysis_id" => analysis.id}
    |> new()
    |> Oban.insert()
  end

  @impl true
  def perform(%Oban.Job{args: %{"analysis_id" => analysis_id}}) do
    Dispatch.run(analysis_id)
    :ok
  end
end
