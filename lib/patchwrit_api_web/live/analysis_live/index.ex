defmodule PatchwritApiWeb.AnalysisLive.Index do
  @moduledoc """
  The Patchwrit docket: what needs attention across tracked
  repositories.

  Attention first (verdicts and policy caps), then repository posture,
  then run history; repository setup is demoted to a secondary panel
  unless the workspace is empty. Tribunal figures come from persisted
  verdicts only — the page renders, never recalculates, outcomes.

  Entering a valid public GitHub URL fetches its branches immediately
  so the user can choose a non-default branch. The Java version is
  manual: the user who tracks the repository specifies the JDK.
  """

  use PatchwritApiWeb, :live_view

  alias PatchwritApi.Analyses
  alias PatchwritApi.Findings
  alias PatchwritApi.GitHub
  alias PatchwritApi.Repositories
  alias PatchwritApi.Repositories.Repository
  alias PatchwritApi.Tribunal
  import PatchwritApiWeb.AnalysisComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign_dashboard()
     |> assign(:branch_options, [])
     |> assign(:branches_for_url, nil)
     |> assign(:branch_state, :idle)
     |> assign(:branch_error, nil)
     |> assign_repository_form(%{})}
  end

  # Recomputed on mount and after a run is queued, so the docket never
  # shows a stale posture.
  defp assign_dashboard(socket) do
    repositories = Repositories.list_repositories()
    analyses = Analyses.list_analyses()

    attention = Tribunal.attention_queue(10)

    socket
    |> assign(:repositories, repositories)
    |> assign(:analyses, analyses)
    |> assign(:stats, dashboard_stats(analyses))
    |> assign(:attention, attention)
    |> assign(:sidebar_summary, [
      %{label: "Tracked", value: Integer.to_string(length(repositories))},
      %{label: "Need attention", value: Integer.to_string(length(attention))},
      %{label: "Model tokens", value: format_number(Tribunal.total_tokens())}
    ])
    |> assign(:postures, repo_postures(repositories, analyses))
    |> assign(:summaries, analysis_summaries(analyses))
  end

  @impl true
  def handle_event("validate_repository", %{"repository" => params}, socket) do
    {params, socket} = maybe_fetch_branches(socket, params)

    changeset =
      %Repository{}
      |> Repository.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :repository_form, to_form(changeset))}
  end

  def handle_event("save_repository", %{"repository" => params}, socket) do
    case Repositories.create_repository(params) do
      {:ok, _repository} ->
        {:noreply,
         socket
         |> put_flash(:info, "Repository tracked")
         |> assign_dashboard()
         |> assign(:branch_options, [])
         |> assign(:branches_for_url, nil)
         |> assign(:branch_state, :idle)
         |> assign(:branch_error, nil)
         |> assign_repository_form(%{})}

      {:error, changeset} ->
        {:noreply, assign(socket, :repository_form, to_form(changeset))}
    end
  end

  def handle_event("run_repository", %{"id" => id}, socket) do
    repository = Repositories.get_repository!(id)

    case Analyses.create_analysis_for_repository(repository) do
      {:ok, analysis} ->
        PatchwritApi.Workers.DispatchAnalysis.enqueue(analysis)

        {:noreply,
         socket
         |> put_flash(:info, "Analysis queued")
         |> assign_dashboard()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not queue analysis")}
    end
  end

  defp maybe_fetch_branches(socket, params) do
    repository_url = Repository.canonical_url(params["repository_url"] || "")

    cond do
      is_nil(repository_url) ->
        {params,
         socket
         |> assign(:branch_options, [])
         |> assign(:branches_for_url, nil)
         |> assign(:branch_state, :idle)
         |> assign(:branch_error, nil)}

      socket.assigns.branches_for_url == repository_url ->
        {params, socket}

      true ->
        case GitHub.repository_branches(repository_url) do
          {:ok, %{default_branch: default_branch, branches: branches}} ->
            params =
              if params["default_ref"] in [nil, "", "HEAD"] or
                   socket.assigns.branches_for_url != repository_url do
                Map.put(params, "default_ref", default_branch || "HEAD")
              else
                params
              end

            {params,
             socket
             |> assign(:branch_options, Enum.map(branches, & &1.name))
             |> assign(:branches_for_url, repository_url)
             |> assign(:branch_state, :loaded)
             |> assign(:branch_error, nil)}

          {:error, message} ->
            {params,
             socket
             |> assign(:branch_options, [])
             |> assign(:branches_for_url, repository_url)
             |> assign(:branch_state, :error)
             |> assign(:branch_error, message)}
        end
    end
  end

  defp assign_repository_form(socket, attrs) do
    changeset = Repository.changeset(%Repository{}, attrs)
    assign(socket, :repository_form, to_form(changeset))
  end

  defp latest_analysis(analyses, repository) do
    Enum.find(analyses, &(&1.repository_id == repository.id))
  end

  # -- dashboard data ---------------------------------------------------------

  @attention_recommendations ~w(remediate_now needs_human_review investigate_usage)
  @recommendation_rank %{
    "remediate_now" => 0,
    "needs_human_review" => 1,
    "investigate_usage" => 2,
    "schedule_remediation" => 3,
    "dismiss" => 4
  }

  defp dashboard_stats(analyses) do
    counts = Tribunal.verdict_recommendation_counts()
    capped = Tribunal.policy_capped_count()
    active = Enum.count(analyses, &(&1.status not in ~w(completed failed cancelled)))
    failed = Enum.count(analyses, &(&1.status == "failed"))

    [
      %{
        value: counts["remediate_now"] || 0,
        label: "Remediate now",
        sub: "Cases the tribunal says to fix first",
        modifier: "pw-stat-card--danger"
      },
      %{
        value: counts["needs_human_review"] || 0,
        label: "Needs human review",
        sub: "#{capped} policy-capped by incomplete evidence",
        modifier: "pw-stat-card--policy"
      },
      %{
        value: counts["investigate_usage"] || 0,
        label: "Investigate usage",
        sub: "Presence proven, exploitability not established",
        modifier: "pw-stat-card--info"
      },
      %{
        value: active,
        label: "Analyses in progress",
        sub: "#{failed} failed · #{length(analyses)} total runs",
        modifier: ""
      }
    ]
  end

  defp repo_postures(repositories, analyses) do
    Map.new(repositories, fn repository ->
      case latest_analysis(analyses, repository) do
        nil ->
          {repository.id, %{latest: nil}}

        latest ->
          verdicts =
            latest.id
            |> Tribunal.latest_verdicts_for_analysis()
            |> Map.values()

          {repository.id,
           %{
             latest: latest,
             findings: Findings.count_findings_for_analysis(latest.id),
             attention: Enum.count(verdicts, &(&1.recommendation in @attention_recommendations)),
             worst: worst_recommendation(verdicts),
             coverage: graph_label(latest),
             evaluated: evaluated_label(latest)
           }}
      end
    end)
  end

  defp worst_recommendation([]), do: nil

  defp worst_recommendation(verdicts) do
    verdicts
    |> Enum.min_by(&Map.get(@recommendation_rank, &1.recommendation, 5))
    |> Map.get(:recommendation)
  end

  defp analysis_summaries(analyses) do
    Map.new(analyses, fn analysis ->
      {analysis.id,
       %{
         findings: Findings.count_findings_for_analysis(analysis.id),
         cases: Tribunal.count_cases_for_analysis(analysis.id),
         judged:
           analysis.id
           |> Tribunal.latest_verdicts_for_analysis()
           |> map_size()
       }}
    end)
  end

  defp graph_label(analysis) do
    graph = analysis.result && analysis.result["graph"]

    cond do
      is_map(graph) and graph["complete"] ->
        "Graph complete (#{graph["modules_resolved"]}/#{graph["modules_total"]} modules)"

      is_map(graph) ->
        "Graph partial (#{graph["modules_resolved"]}/#{graph["modules_total"]} modules)"

      analysis.status == "completed" ->
        "Graph completeness unknown"

      true ->
        "Not yet evaluated"
    end
  end

  defp case_graph_label(case_record) do
    dossier = case_record.dossier_snapshot || %{}
    graph = dossier["graph"] || %{}

    cond do
      graph["complete"] == true ->
        "graph complete"

      is_integer(graph["modules_total"]) ->
        "graph #{graph["modules_resolved"]}/#{graph["modules_total"]} modules"

      true ->
        "graph completeness unknown"
    end
  end

  defp evaluated_label(analysis) do
    if analysis.osv_scanned_at do
      "Evaluated #{Calendar.strftime(analysis.osv_scanned_at, "%Y-%m-%d")}"
    else
      "Updated #{Calendar.strftime(analysis.updated_at, "%Y-%m-%d")}"
    end
  end

  defp one_line(nil), do: nil

  defp one_line(text) do
    if String.length(text) > 220, do: String.slice(text, 0, 220) <> "…", else: text
  end

  defp format_number(number) do
    number
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  defp repo_short_name(repository_url) do
    repository_url
    |> String.trim_trailing("/")
    |> String.trim_trailing(".git")
    |> String.split("/")
    |> Enum.take(-2)
    |> Enum.join("/")
  end

  # -- setup panel (used prominently when empty, demoted otherwise) -----------

  attr :repository_form, :any, required: true
  attr :branch_options, :list, required: true
  attr :branch_state, :atom, required: true
  attr :branch_error, :string, required: true

  defp repository_setup(assigns) do
    ~H"""
    <section class="pw-panel" aria-labelledby="track-repository-title">
      <span class="pw-panel-kicker">New repository</span>
      <h2 id="track-repository-title">Track a repository</h2>
      <p class="pw-panel-copy">
        Branches load from GitHub as soon as a valid repository link is entered. The Java version stays manual—you know your project best.
      </p>

      <.form
        for={@repository_form}
        id="repository-form"
        phx-change="validate_repository"
        phx-submit="save_repository"
        class="pw-form"
      >
        <.input
          field={@repository_form[:repository_url]}
          label="Repository URL"
          placeholder="https://github.com/owner/repo"
          phx-debounce="400"
        />

        <.input
          :if={@branch_options != []}
          field={@repository_form[:default_ref]}
          type="select"
          label="Branch"
          options={@branch_options}
        />
        <.input
          :if={@branch_options == []}
          field={@repository_form[:default_ref]}
          label="Branch / ref"
          placeholder="main"
        />
        <p :if={@branch_state == :loaded} class="pw-branch-note">
          Branches loaded from GitHub. The default branch is selected.
        </p>
        <p :if={@branch_state == :error} class="pw-branch-error">
          Could not load branches: {@branch_error} You can still enter a branch or ref manually.
        </p>

        <.input
          field={@repository_form[:java_version]}
          type="select"
          label="Java version"
          options={["JDK 17": "17", "JDK 21": "21"]}
        />
        <button type="submit" class="pw-submit">Track repository</button>
      </.form>
    </section>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="pw-app">
      <.app_sidebar active="docket" summary={@sidebar_summary} />

      <main class="pw-main">
        <div class="pw-docket-head">
          <h1>Your security docket</h1>
          <p>
            What needs your attention across tracked repositories—tribunal verdicts first, evidence one click away.
          </p>
        </div>

        <section class="pw-stat-strip" aria-label="Attention summary">
          <div :for={stat <- @stats} class={["pw-stat-card", stat.modifier]}>
            <span class="pw-stat-value">{stat.value}</span>
            <span class="pw-stat-label">{stat.label}</span>
            <span class="pw-stat-sub">{stat.sub}</span>
          </div>
        </section>

        <.repository_setup
          :if={@repositories == []}
          repository_form={@repository_form}
          branch_options={@branch_options}
          branch_state={@branch_state}
          branch_error={@branch_error}
        />

        <section class="pw-dashboard-section" aria-labelledby="needs-attention-title">
          <div class="pw-section-head">
            <div>
              <span class="pw-panel-kicker">Tribunal</span>
              <h2 id="needs-attention-title">Needs attention</h2>
            </div>
            <span class="pw-count">{length(@attention)} cases</span>
          </div>

          <div :if={@attention == []} class="pw-empty">
            <strong>Nothing needs attention</strong>
            No completed tribunal verdict currently asks for remediation, human review, or usage investigation.
          </div>

          <ul :if={@attention != []} class="pw-analysis-list">
            <li :for={verdict <- @attention} class="pw-analysis-row pw-attention-row">
              <div>
                <.link
                  navigate={~p"/analyses/#{verdict.tribunal_case.analysis_id}"}
                  class="pw-repo-link"
                >
                  {repo_short_name(verdict.tribunal_case.analysis.repository_url)} · {verdict.tribunal_case.finding.package_name}:{verdict.tribunal_case.finding.package_version}
                </.link>
                <div class="pw-meta">
                  <span class="pw-mono">{verdict.tribunal_case.finding.osv_id}</span>
                  <span>presence: {verdict.presence}</span>
                  <span>exploitability: {verdict.exploitability}</span>
                  <span>priority: {verdict.priority}</span>
                  <span>{case_graph_label(verdict.tribunal_case)}</span>
                </div>
                <p :if={verdict.rationale} class="pw-attention-why">{one_line(verdict.rationale)}</p>
              </div>
              <div class="pw-attention-badges">
                <.policy_capped_badge verdict={verdict} />
                <.verdict_badge recommendation={verdict.recommendation} />
              </div>
            </li>
          </ul>
        </section>

        <section class="pw-dashboard-section" aria-labelledby="tracked-repositories-title">
          <div class="pw-section-head">
            <div>
              <span class="pw-panel-kicker">Library</span>
              <h2 id="tracked-repositories-title">Your repositories</h2>
            </div>
            <span class="pw-count">{length(@repositories)} tracked</span>
          </div>

          <div :if={@repositories == []} class="pw-empty">
            <strong>No tracked repositories yet</strong>
            Add one from the form and it will be ready to run.
          </div>

          <ul :if={@repositories != []} class="pw-analysis-list">
            <li :for={repository <- @repositories} class="pw-analysis-row">
              <span class="pw-repo-link">{repository.repository_url}</span>
              <div class="pw-meta">
                <span>branch: <span class="pw-mono">{repository.default_ref}</span></span>
                <span>JDK {repository.java_version}</span>
                <%= if (posture = @postures[repository.id]).latest do %>
                  <.status_badge status={posture.latest.status} />
                  <span>{posture.findings} findings</span>
                  <span>{posture.attention} need attention</span>
                  <span>{posture.coverage}</span>
                  <span>{posture.evaluated}</span>
                  <.verdict_badge :if={posture.worst} recommendation={posture.worst} />
                <% else %>
                  <span>No runs yet</span>
                <% end %>
              </div>
              <button
                id={"run-repository-#{repository.id}"}
                type="button"
                class="pw-run-button"
                phx-click="run_repository"
                phx-value-id={repository.id}
              >
                Run analysis
              </button>
            </li>
          </ul>
        </section>

        <section class="pw-dashboard-section" aria-labelledby="recent-analyses-title">
          <div class="pw-section-head">
            <div>
              <span class="pw-panel-kicker">History</span>
              <h2 id="recent-analyses-title">Recent analyses</h2>
            </div>
            <span class="pw-count">{length(@analyses)} total</span>
          </div>

          <div :if={@analyses == []} class="pw-empty">
            <strong>No analyses yet</strong>
            Run a tracked repository and the analysis will appear here.
          </div>

          <ul :if={@analyses != []} class="pw-analysis-list">
            <li :for={analysis <- @analyses} class="pw-analysis-row">
              <.link navigate={~p"/analyses/#{analysis.id}"} class="pw-repo-link">
                {analysis.repository_url}
              </.link>
              <div class="pw-meta">
                <span>ref: <span class="pw-mono">{analysis.requested_ref}</span></span>
                <span :if={analysis.jdk_version}>JDK {analysis.jdk_version}</span>
                <.status_badge status={analysis.status} />
                <.cleanup_badge status={analysis.machine_cleanup_status} />
                <span :if={@summaries[analysis.id].cases > 0} class="pw-progress-note">
                  {@summaries[analysis.id].findings} findings · tribunal {@summaries[analysis.id].judged}/{@summaries[
                    analysis.id
                  ].cases} judged
                </span>
              </div>
            </li>
          </ul>
        </section>

        <section :if={@repositories != []} class="pw-dashboard-section" aria-label="Repository setup">
          <.repository_setup
            repository_form={@repository_form}
            branch_options={@branch_options}
            branch_state={@branch_state}
            branch_error={@branch_error}
          />
        </section>
      </main>
    </div>
    """
  end
end
