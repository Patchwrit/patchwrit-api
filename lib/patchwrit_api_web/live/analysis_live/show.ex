defmodule PatchwritApiWeb.AnalysisLive.Show do
  @moduledoc "Detail view for one persisted Analysis."

  use PatchwritApiWeb, :live_view

  alias PatchwritApi.Analyses
  import PatchwritApiWeb.AnalysisComponents

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok, assign(socket, :analysis, Analyses.get_analysis!(id))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-3xl px-4 py-8">
      <.link navigate={~p"/analyses"} class="text-sm text-zinc-600 underline">← All analyses</.link>
      <h1 class="mt-3 break-all text-xl font-bold text-zinc-900">{@analysis.repository_url}</h1>

      <div class="mt-3 flex items-center gap-2">
        <.status_badge status={@analysis.status} />
        <.cleanup_badge status={@analysis.machine_cleanup_status} />
      </div>

      <dl class="mt-6 space-y-2 text-sm">
        <div>
          <dt class="font-semibold text-zinc-900">ID</dt>
          <dd class="break-all text-zinc-700">{@analysis.id}</dd>
        </div>
        <div>
          <dt class="font-semibold text-zinc-900">Requested ref</dt>
          <dd class="text-zinc-700">{@analysis.requested_ref}</dd>
        </div>
        <div>
          <dt class="font-semibold text-zinc-900">Resolved SHA</dt>
          <dd class="text-zinc-700">{@analysis.resolved_sha || "—"}</dd>
        </div>
        <div>
          <dt class="font-semibold text-zinc-900">Machine</dt>
          <dd class="text-zinc-700">{@analysis.machine_id || "—"}</dd>
        </div>
        <div>
          <dt class="font-semibold text-zinc-900">Worker image</dt>
          <dd class="text-zinc-700">{@analysis.worker_image || "—"}</dd>
        </div>
        <div :if={@analysis.error_category}>
          <dt class="font-semibold text-zinc-900">Error</dt>
          <dd class="text-zinc-700">{@analysis.error_category}: {@analysis.error_message}</dd>
        </div>
      </dl>

      <section :if={@analysis.result} class="mt-6">
        <h2 class="text-base font-semibold text-zinc-900">Worker result</h2>
        <pre class="mt-2 overflow-x-auto rounded bg-zinc-950 p-4 text-xs text-zinc-100">{Jason.encode!(@analysis.result, pretty: true)}</pre>
      </section>
    </div>
    """
  end
end
