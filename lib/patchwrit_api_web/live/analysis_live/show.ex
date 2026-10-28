defmodule PatchwritApiWeb.AnalysisLive.Show do
  @moduledoc "Detail view for one persisted Analysis."

  use PatchwritApiWeb, :live_view

  alias PatchwritApi.Analyses
  alias PatchwritApi.Findings
  import PatchwritApiWeb.AnalysisComponents

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    analysis = Analyses.get_analysis!(id)

    {:ok,
     socket
     |> assign(:analysis, analysis)
     |> assign(:findings, Findings.list_findings_for_analysis(analysis.id))
     |> assign(:introduced_via, introduced_via_map(analysis))}
  end

  defp via_label(introduced_via, finding) do
    key = "#{finding.package_name}:#{finding.package_version}"

    case Map.get(introduced_via, key) do
      [_ | _] = path -> "via #{List.last(path)}"
      _ -> nil
    end
  end

  # package "group:artifact:version" -> introduction path from the graph,
  # so a finding can show how the vulnerable package entered the build.
  defp introduced_via_map(analysis) do
    dependencies = get_in(analysis.result || %{}, ["dependencies"]) || []

    Map.new(dependencies, fn dep ->
      {"#{dep["group_id"]}:#{dep["artifact_id"]}:#{dep["version"]}", dep["introduced_via"] || []}
    end)
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
            <dt>Java version</dt>
            <dd>
              {if @analysis.jdk_version, do: "JDK #{@analysis.jdk_version}", else: "Not specified"}
            </dd>
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

        <section :if={@analysis.result && @analysis.result["repository"]} class="pw-result">
          <div class="pw-result-head">
            <div>
              <span class="pw-panel-kicker">Checkout evidence</span>
              <h2>Repository checkout</h2>
            </div>
            <p>Cloned and verified inside the worker Machine.</p>
          </div>
          <dl class="pw-detail-grid">
            <div class="pw-detail-item">
              <dt>Checked-out SHA</dt>
              <dd class="pw-mono">{@analysis.result["repository"]["checked_out_sha"]}</dd>
            </div>
            <div class="pw-detail-item">
              <dt>POM files</dt>
              <dd class="pw-mono">
                {Enum.join(@analysis.result["repository"]["pom_files"] || [], ", ")}
              </dd>
            </div>
          </dl>
        </section>

        <section :if={@analysis.result && @analysis.result["dependencies"]} class="pw-result">
          <div class="pw-result-head">
            <div>
              <span class="pw-panel-kicker">Maven graph</span>
              <h2>Dependencies ({length(@analysis.result["dependencies"])})</h2>
            </div>
            <p>Effective graph from the pinned checkout. First 50 shown.</p>
          </div>
          <ul class="pw-analysis-list">
            <li :for={dep <- Enum.take(@analysis.result["dependencies"], 50)} class="pw-analysis-row">
              <span class="pw-mono">{dep["group_id"]}:{dep["artifact_id"]}:{dep["version"]}</span>
              <div class="pw-meta">
                <span>depth {dep["depth"]}</span>
                <span :if={dep["scope"]}>scope {dep["scope"]}</span>
                <span>via {dep["introduced_via"] |> List.last()}</span>
              </div>
            </li>
          </ul>
        </section>

        <section :if={@analysis.status == "completed"} class="pw-result">
          <div class="pw-result-head">
            <div>
              <span class="pw-panel-kicker">OSV scan</span>
              <h2>Findings ({length(@findings)})</h2>
            </div>
            <p :if={@analysis.osv_scanned_at}>
              Scanned {Calendar.strftime(@analysis.osv_scanned_at, "%Y-%m-%d %H:%M:%S UTC")} against OSV.
            </p>
            <p :if={!@analysis.osv_scanned_at}>
              Not yet scanned. The scan runs automatically after a completed run.
            </p>
          </div>
          <p :if={@analysis.osv_scanned_at && @findings == []}>
            No known vulnerabilities in the scanned dependencies.
          </p>
          <ul class="pw-analysis-list">
            <li :for={finding <- @findings} class="pw-analysis-row">
              <span class="pw-mono">{finding.package_name}:{finding.package_version}</span>
              <span :if={finding.summary}>{finding.summary}</span>
              <div class="pw-meta">
                <span>{finding.osv_id}</span>
                <span :for={alias_name <- finding.aliases}>{alias_name}</span>
                <span :if={finding.severity}>{finding.severity}</span>
                <span>
                  {if finding.fixed_versions == [],
                    do: "no fix published",
                    else: "fixed in #{Enum.join(finding.fixed_versions, ", ")}"}
                </span>
                <span :if={via_label(@introduced_via, finding)}>
                  {via_label(@introduced_via, finding)}
                </span>
              </div>
            </li>
          </ul>
        </section>

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
