defmodule PatchwritApiWeb.AnalysisLive.History do
  @moduledoc """
  Analysis history: every run across tracked repositories, newest
  first, with persisted findings and tribunal progress per run.

  Failed runs stay visible beside successful ones; tribunal figures
  come from persisted verdicts only.
  """

  use PatchwritApiWeb, :live_view

  alias PatchwritApi.Analyses
  alias PatchwritApi.Findings
  alias PatchwritApi.Repositories.Repository
  alias PatchwritApi.Tribunal
  alias PatchwritApiWeb.RepoPosture
  import PatchwritApiWeb.AnalysisComponents

  @impl true
  def mount(_params, _session, socket) do
    analyses = Analyses.list_analyses()

    rows =
      Enum.map(analyses, fn analysis ->
        verdicts =
          analysis.id
          |> Tribunal.latest_verdicts_for_analysis()
          |> Map.values()

        %{
          analysis: analysis,
          name: Repository.name_from_url(analysis.repository_url) || analysis.repository_url,
          findings: Findings.count_findings_for_analysis(analysis.id),
          cases: Tribunal.count_cases_for_analysis(analysis.id),
          judged: length(verdicts),
          worst: RepoPosture.worst_verdict(verdicts)
        }
      end)

    {:ok, assign(socket, rows: rows, total: length(rows))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="pw-app">
      <.app_sidebar active="analyses" />

      <main class="pw-main">
        <div class="pw-docket-head">
          <div>
            <h1>Analyses</h1>
            <p>
              Every run across tracked repositories—newest first, failures never hidden.
            </p>
          </div>
        </div>

        <section aria-labelledby="analyses-table-title">
          <div class="pw-section-head">
            <div>
              <span class="pw-panel-kicker">History</span>
              <h2 id="analyses-table-title">All analyses</h2>
            </div>
            <span class="pw-count">{@total} total</span>
          </div>

          <div :if={@rows == []} class="pw-empty">
            <strong>No analyses yet</strong>
            Run a tracked repository and the analysis will appear here.
          </div>

          <div :if={@rows != []} class="pw-table-wrap">
            <table class="pw-table">
              <thead>
                <tr>
                  <th>Repository</th>
                  <th>Status</th>
                  <th>Findings</th>
                  <th>Tribunal</th>
                  <th>Tribunal status</th>
                  <th>Cleanup</th>
                  <th>Started</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={row <- @rows}>
                  <td data-label="Repository">
                    <.link navigate={~p"/analyses/#{row.analysis.id}"} class="pw-repo-link">
                      {row.name}
                    </.link>
                    <div class="pw-repo-sub">
                      {row.analysis.requested_ref}<span :if={row.analysis.jdk_version}>
                        · JDK {row.analysis.jdk_version}
                      </span>
                      <span :if={row.analysis.resolved_sha}>
                        · {String.slice(row.analysis.resolved_sha, 0, 7)}
                      </span>
                    </div>
                  </td>
                  <td data-label="Status">
                    <.status_badge status={row.analysis.status} />
                  </td>
                  <td data-label="Findings">{row.findings}</td>
                  <td data-label="Tribunal">
                    <span :if={row.cases > 0}>{row.judged}/{row.cases} judged</span>
                    <span :if={row.cases == 0} class="pw-muted">—</span>
                  </td>
                  <td data-label="Tribunal status">
                    <.verdict_badge :if={row.worst} recommendation={row.worst} />
                    <span :if={!row.worst && row.cases > 0} class="pw-muted">Not judged</span>
                    <span
                      :if={!row.worst && row.cases == 0 && row.analysis.osv_scanned_at}
                      class="pw-clean-note"
                    >
                      Clean scan
                    </span>
                    <span
                      :if={!row.worst && row.cases == 0 && !row.analysis.osv_scanned_at}
                      class="pw-muted"
                    >
                      —
                    </span>
                  </td>
                  <td data-label="Cleanup">
                    <.cleanup_badge status={row.analysis.machine_cleanup_status} />
                  </td>
                  <td data-label="Started">
                    <span class="pw-mono">
                      {Calendar.strftime(row.analysis.inserted_at, "%Y-%m-%d %H:%M")}
                    </span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
      </main>
    </div>
    """
  end
end
