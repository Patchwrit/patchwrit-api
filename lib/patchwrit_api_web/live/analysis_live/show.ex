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
    <div class="pw-shell">
      <header class="pw-masthead">
        <.link navigate={~p"/analyses"} class="pw-brand">
          <span class="pw-mark">PW</span>
          <span class="pw-brand-copy">
            <strong>Patchwrit</strong>
            <span>Analysis console</span>
          </span>
        </.link>
        <p class="pw-masthead-note">Ephemeral Fly workers<br />Evidence-first results</p>
      </header>

      <main>
        <.link navigate={~p"/analyses"} class="pw-back-link">← All analyses</.link>
        <h1 class="pw-detail-title">{@analysis.repository_url}</h1>

        <div class="pw-status-strip">
          <.status_badge status={@analysis.status} />
          <.cleanup_badge status={@analysis.machine_cleanup_status} />
        </div>

        <dl class="pw-detail-grid">
          <div class="pw-detail-item">
            <dt>Analysis ID</dt>
            <dd class="pw-mono">{@analysis.id}</dd>
          </div>
          <div class="pw-detail-item">
            <dt>Requested ref</dt>
            <dd class="pw-mono">{@analysis.requested_ref}</dd>
          </div>
          <div class="pw-detail-item">
            <dt>Resolved SHA</dt>
            <dd class="pw-mono">{@analysis.resolved_sha || "Not pinned yet"}</dd>
          </div>
          <div class="pw-detail-item">
            <dt>Fly Machine</dt>
            <dd class="pw-mono">{@analysis.machine_id || "Not provisioned"}</dd>
          </div>
          <div class="pw-detail-item">
            <dt>Worker image</dt>
            <dd class="pw-mono">{@analysis.worker_image || "Not selected yet"}</dd>
          </div>
          <div class="pw-detail-item">
            <dt>Last updated</dt>
            <dd>{Calendar.strftime(@analysis.updated_at, "%Y-%m-%d %H:%M:%S UTC")}</dd>
          </div>
        </dl>

        <div :if={@analysis.error_category} class="pw-error">
          <strong>{@analysis.error_category}</strong>
          <span :if={@analysis.error_message}>{@analysis.error_message}</span>
        </div>

        <section :if={@analysis.result} class="pw-result">
          <div class="pw-result-head">
            <div>
              <span class="pw-panel-kicker">Worker evidence</span>
              <h2>Worker result</h2>
            </div>
            <p>Raw callback payload, stored as received.</p>
          </div>
          <pre class="pw-terminal">{Jason.encode!(@analysis.result, pretty: true)}</pre>
        </section>
      </main>
    </div>
    """
  end
end
