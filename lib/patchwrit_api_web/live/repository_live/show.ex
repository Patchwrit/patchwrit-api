defmodule PatchwritApiWeb.RepositoryLive.Show do
  @moduledoc """
  Repository detail: configuration, latest known posture, and every
  run of this repository — the parent level of the
  repository → run → finding hierarchy.
  """

  use PatchwritApiWeb, :live_view

  alias PatchwritApi.Analyses
  alias PatchwritApi.Findings
  alias PatchwritApi.Repositories
  alias PatchwritApi.Repositories.Repository
  alias PatchwritApi.Tribunal
  alias PatchwritApiWeb.RepoPosture
  import PatchwritApiWeb.AnalysisComponents

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    repository = Repositories.get_repository!(id)
    {:ok, assign_page(socket, repository)}
  end

  defp assign_page(socket, repository) do
    runs = Analyses.list_analyses_for_repository(repository.id)
    postures = RepoPosture.postures([repository], Analyses.list_analyses())
    posture = postures[repository.id]

    run_rows =
      Enum.map(runs, fn analysis ->
        verdicts =
          analysis.id
          |> Tribunal.latest_verdicts_for_analysis()
          |> Map.values()

        %{
          analysis: analysis,
          findings: Findings.count_findings_for_analysis(analysis.id),
          cases: Tribunal.count_cases_for_analysis(analysis.id),
          judged: length(verdicts),
          worst: worst_verdict(verdicts)
        }
      end)

    socket
    |> assign(:repository, repository)
    |> assign(:posture, posture)
    |> assign(:runs, run_rows)
  end

  @impl true
  def handle_event("run_repository", %{"id" => id}, socket) do
    repository = Repositories.get_repository!(id)

    case Analyses.create_analysis_for_repository(repository) do
      {:ok, analysis} ->
        PatchwritApi.Workers.DispatchAnalysis.enqueue(analysis)

        {:noreply,
         socket
         |> put_flash(:info, "Analysis queued")
         |> assign_page(repository)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not queue analysis")}
    end
  end

  defp clean_scan?(posture) do
    posture.latest && posture.latest.osv_scanned_at && posture.findings == 0
  end

  @recommendation_rank %{
    "remediate_now" => 0,
    "needs_human_review" => 1,
    "investigate_usage" => 2,
    "schedule_remediation" => 3,
    "dismiss" => 4
  }

  defp worst_verdict([]), do: nil

  defp worst_verdict(verdicts) do
    verdicts
    |> Enum.min_by(&Map.get(@recommendation_rank, &1.recommendation, 5))
    |> Map.get(:recommendation)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="pw-app">
      <.app_sidebar active="repositories" />

      <main class="pw-main">
        <.link navigate={~p"/repositories"} class="pw-back-link">← All repositories</.link>
        <h1 class="pw-detail-title">{Repository.display_name(@repository)}</h1>

        <div class="pw-status-strip">
          <span :if={@posture.latest}>
            <.status_badge status={@posture.latest.status} />
          </span>
          <.verdict_badge :if={@posture.worst} recommendation={@posture.worst} />
          <span :if={!@posture.worst && clean_scan?(@posture)} class="pw-clean-note">
            Clean scan
          </span>
        </div>

        <dl class="pw-detail-grid">
          <div class="pw-detail-item">
            <dt>Repository URL</dt>
            <dd class="pw-mono">{@repository.repository_url}</dd>
          </div>
          <div class="pw-detail-item">
            <dt>Default branch</dt>
            <dd class="pw-mono">{@repository.default_ref}</dd>
          </div>
          <div class="pw-detail-item">
            <dt>Java version</dt>
            <dd>JDK {@repository.java_version}</dd>
          </div>
          <div class="pw-detail-item">
            <dt>Latest coverage</dt>
            <dd>{@posture.coverage}</dd>
          </div>
          <div class="pw-detail-item">
            <dt>Latest findings</dt>
            <dd>{if @posture.latest, do: @posture.findings, else: "—"}</dd>
          </div>
          <div class="pw-detail-item">
            <dt>Action needed (latest run)</dt>
            <dd>{if @posture.latest, do: @posture.attention, else: "—"}</dd>
          </div>
        </dl>

        <div class="pw-repo-actions-row">
          <button
            id={"run-repository-#{@repository.id}"}
            type="button"
            class="pw-run-button"
            phx-click="run_repository"
            phx-value-id={@repository.id}
          >
            Run analysis
          </button>
          <span class="pw-count">{length(@runs)} runs</span>
        </div>

        <section class="pw-result" aria-labelledby="repo-runs-title">
          <div class="pw-result-head">
            <div>
              <span class="pw-panel-kicker">Runs</span>
              <h2 id="repo-runs-title">Analysis history</h2>
            </div>
            <p>Newest first. Select a run to see its findings and tribunal cases.</p>
          </div>

          <div :if={@runs == []} class="pw-empty">
            <strong>No runs yet</strong> Run this repository and its first analysis will appear here.
          </div>

          <div :if={@runs != []} class="pw-table-wrap">
            <table class="pw-table">
              <thead>
                <tr>
                  <th>Started</th>
                  <th>SHA</th>
                  <th>Status</th>
                  <th>Findings</th>
                  <th>Tribunal</th>
                  <th>Tribunal status</th>
                  <th>Cleanup</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={row <- @runs}>
                  <td data-label="Started">
                    <.link navigate={~p"/analyses/#{row.analysis.id}"} class="pw-repo-link">
                      {Calendar.strftime(row.analysis.inserted_at, "%Y-%m-%d %H:%M")}
                    </.link>
                  </td>
                  <td data-label="SHA">
                    <span class="pw-mono">
                      {if row.analysis.resolved_sha,
                        do: String.slice(row.analysis.resolved_sha, 0, 7),
                        else: "—"}
                    </span>
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
