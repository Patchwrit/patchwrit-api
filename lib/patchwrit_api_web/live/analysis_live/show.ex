defmodule PatchwritApiWeb.AnalysisLive.Show do
  @moduledoc "Detail view for one persisted Analysis."

  use PatchwritApiWeb, :live_view

  alias PatchwritApi.Analyses
  alias PatchwritApi.Findings
  alias PatchwritApi.Tribunal
  alias PatchwritApi.Tribunal.Triage
  alias PatchwritApi.Workers.RunTribunalCase
  import PatchwritApiWeb.AnalysisComponents

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    analysis = Analyses.get_analysis!(id)
    findings = Findings.list_findings_for_analysis(analysis.id)

    cases_by_finding =
      Map.new(Tribunal.list_cases_for_analysis(analysis.id), &{&1.finding_id, &1})

    verdicts_by_case = Tribunal.latest_verdicts_for_analysis(analysis.id)
    failed_cases = Tribunal.failed_case_ids(analysis.id)

    rows =
      findings
      |> Enum.map(fn finding ->
        case_record = cases_by_finding[finding.id]

        %{
          finding: finding,
          case: case_record,
          verdict: case_record && verdicts_by_case[case_record.id],
          failed: case_record != nil and MapSet.member?(failed_cases, case_record.id)
        }
      end)
      |> Enum.sort_by(&row_sort_key/1)

    {:ok,
     socket
     |> assign(:analysis, analysis)
     |> assign(:findings, findings)
     |> assign(:finding_rows, rows)
     |> assign(:expanded_finding_id, nil)
     |> assign(:expanded_opinions, [])
     |> assign(:queued_case_ids, MapSet.new())
     |> assign(:introduced_via, introduced_via_map(analysis))}
  end

  @impl true
  def handle_event("toggle_finding", %{"id" => finding_id}, socket) do
    if socket.assigns.expanded_finding_id == finding_id do
      {:noreply,
       socket
       |> assign(:expanded_finding_id, nil)
       |> assign(:expanded_opinions, [])}
    else
      opinions =
        case Enum.find(socket.assigns.finding_rows, &(&1.finding.id == finding_id)) do
          %{case: %{id: case_id}} -> Tribunal.list_opinions_for_case(case_id)
          _ -> []
        end

      {:noreply,
       socket
       |> assign(:expanded_finding_id, finding_id)
       |> assign(:expanded_opinions, opinions)}
    end
  end

  def handle_event("run_tribunal", %{"id" => case_id}, socket) do
    case Tribunal.get_case(case_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Tribunal case not found")}

      case_record ->
        RunTribunalCase.enqueue(case_record)

        {:noreply,
         socket
         |> put_flash(:info, "Tribunal queued for this case")
         |> assign(:queued_case_ids, MapSet.put(socket.assigns.queued_case_ids, case_id))}
    end
  end

  # Worst tribunal outcome first; failed attempts next; unjudged last.
  @recommendation_rank %{
    "remediate_now" => 0,
    "needs_human_review" => 1,
    "investigate_usage" => 2,
    "schedule_remediation" => 3,
    "dismiss" => 4
  }

  defp row_sort_key(%{verdict: %{recommendation: recommendation}, finding: finding}) do
    {0, Map.get(@recommendation_rank, recommendation, 5), finding.package_name, finding.osv_id}
  end

  defp row_sort_key(%{failed: true, finding: finding}) do
    {1, 0, finding.package_name, finding.osv_id}
  end

  defp row_sort_key(%{case: case_record, finding: finding}) when not is_nil(case_record) do
    {2, 0, finding.package_name, finding.osv_id}
  end

  defp row_sort_key(%{finding: finding}) do
    {3, 0, finding.package_name, finding.osv_id}
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
      path = (dep["introduction_paths"] || []) |> List.first(dep["introduced_via"] || [])
      {"#{dep["group_id"]}:#{dep["artifact_id"]}:#{dep["version"]}", path}
    end)
  end

  # -- tribunal case panel helpers ---------------------------------------------

  defp dossier_for(nil), do: %{}

  defp dossier_for(case_record) do
    case case_record.dossier_snapshot do
      snapshot when is_map(snapshot) and snapshot != %{} -> snapshot
      _ -> case_record.packet || %{}
    end
  end

  defp latest_opinion(opinions, role, status) do
    opinions
    |> Enum.filter(&(&1.role == role and &1.status == status))
    |> List.last()
  end

  defp case_tokens(opinions, verdict) do
    opinion_tokens = Enum.sum_by(opinions, &(&1.usage["total_tokens"] || 0))
    verdict_tokens = if verdict, do: verdict.usage["total_tokens"] || 0, else: 0
    opinion_tokens + verdict_tokens
  end

  defp triage_reason(case_record) do
    dossier = dossier_for(case_record)
    artifact = dossier["artifact"] || %{}
    advisories = dossier["advisories"] || []
    severity? = Enum.any?(advisories, &(is_binary(&1["severity"]) and &1["severity"] != ""))

    cond do
      Triage.eligible?(case_record) ->
        "Selected by triage; the tribunal has not run yet."

      not severity? ->
        "Not selected by triage: no severity was reported for this advisory."

      artifact["direct"] != true ->
        "Not selected by triage: transitive #{artifact["scope"] || "unknown"}-scope dependency."

      true ->
        "Not selected by triage."
    end
  end

  defp graph_text(dossier) do
    graph = dossier["graph"] || %{}

    cond do
      graph["complete"] == true ->
        "complete (#{graph["modules_resolved"]}/#{graph["modules_total"]} modules)"

      is_integer(graph["modules_total"]) ->
        "partial (#{graph["modules_resolved"]}/#{graph["modules_total"]} modules)"

      true ->
        "completeness unknown"
    end
  end

  defp range_text(range) do
    events =
      Enum.map_join(range["events"] || [], ", ", fn event ->
        cond do
          event["introduced"] -> "introduced #{event["introduced"]}"
          event["fixed"] -> "fixed #{event["fixed"]}"
          event["last_affected"] -> "last affected #{event["last_affected"]}"
          true -> ""
        end
      end)

    "#{range["type"]}: #{events}"
  end

  attr :case, :map, required: true

  # Collapsed evidence dossier for one case: artifact, advisory ranges,
  # introduction paths, graph state, and explicit missing context.
  defp case_dossier(assigns) do
    assigns = assign(assigns, :dossier, dossier_for(assigns.case))

    ~H"""
    <details class="pw-dossier">
      <summary>
        Evidence dossier · graph {graph_text(@dossier)}<span :if={@case.snapshot_hash}>
          · snapshot {@case.snapshot_hash}
        </span>
      </summary>
      <dl class="pw-detail-grid">
        <div class="pw-detail-item">
          <dt>Artifact</dt>
          <dd class="pw-mono">
            {(@dossier["artifact"] || %{})["group_id"]}:{(@dossier["artifact"] || %{})[
              "artifact_id"
            ]}:{(@dossier["artifact"] || %{})["resolved_version"]}
          </dd>
        </div>
        <div class="pw-detail-item">
          <dt>Scope / direct</dt>
          <dd>
            {(@dossier["artifact"] || %{})["scope"] || "unknown"} · {if (@dossier["artifact"] ||
                                                                           %{})["direct"],
                                                                        do: "direct",
                                                                        else: "transitive"}
          </dd>
        </div>
        <div :for={advisory <- @dossier["advisories"] || []} class="pw-detail-item">
          <dt>Advisory {advisory["id"]}</dt>
          <dd>
            <span :if={advisory["severity"]}>{advisory["severity"]}<br /></span>
            <span :for={range <- advisory["affected_ranges"] || []}>
              {range_text(range)}<br />
            </span>
            <span :for={reference <- advisory["references"] || []}>
              <a href={reference} target="_blank" rel="noreferrer">{reference}</a> <br />
            </span>
          </dd>
        </div>
        <div class="pw-detail-item">
          <dt>Introduction paths</dt>
          <dd class="pw-mono">
            <span :for={path <- (@dossier["artifact"] || %{})["introduction_paths"] || []}>
              {Enum.join(path, " → ")}<br />
            </span>
            <span :if={((@dossier["artifact"] || %{})["introduction_paths"] || []) == []}>
              none recorded
            </span>
          </dd>
        </div>
        <div class="pw-detail-item">
          <dt>Missing context</dt>
          <dd>
            <span :for={item <- @dossier["missing_context"] || []}>{item}<br /></span>
            <span :if={(@dossier["missing_context"] || []) == []}>none recorded</span>
          </dd>
        </div>
        <div class="pw-detail-item">
          <dt>Collection</dt>
          <dd class="pw-mono">
            worker {(@dossier["collection"] || %{})["worker_image"] || "unknown"}
          </dd>
        </div>
      </dl>
    </details>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="pw-app">
      <.app_sidebar active="analysis" />

      <main class="pw-main">
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
            <p :if={@analysis.result["graph"] && @analysis.result["graph"]["complete"]}>
              Graph complete ({@analysis.result["graph"]["modules_resolved"]}/{@analysis.result[
                "graph"
              ]["modules_total"]} modules).
            </p>
            <p :if={@analysis.result["graph"] && !@analysis.result["graph"]["complete"]}>
              Graph partial ({@analysis.result["graph"]["modules_resolved"]}/{@analysis.result[
                "graph"
              ]["modules_total"]} modules) — findings cover the observed subset only.
            </p>
            <p :if={!@analysis.result["graph"]}>
              Legacy result — graph completeness unknown.
            </p>
          </div>
          <ul class="pw-analysis-list">
            <li :for={dep <- Enum.take(@analysis.result["dependencies"], 50)} class="pw-analysis-row">
              <span class="pw-mono">{dep["group_id"]}:{dep["artifact_id"]}:{dep["version"]}</span>
              <div class="pw-meta">
                <span>depth {dep["depth"]}</span>
                <span :if={dep["scope"]}>scope {dep["scope"]}</span>
                <span :if={dep["module"]}>module {dep["module"]}</span>
                <span>via {(dep["introduction_paths"] || []) |> List.first([]) |> List.last()}</span>
              </div>
            </li>
          </ul>
        </section>

        <section :if={@analysis.status == "completed"} class="pw-result">
          <div class="pw-result-head">
            <div>
              <span class="pw-panel-kicker">OSV scan + tribunal</span>
              <h2>Findings ({length(@findings)})</h2>
            </div>
            <p :if={@analysis.osv_scanned_at}>
              Scanned {Calendar.strftime(@analysis.osv_scanned_at, "%Y-%m-%d %H:%M:%S UTC")} against OSV.
              Select a finding to see its tribunal case.
            </p>
            <p :if={!@analysis.osv_scanned_at}>
              Not yet scanned. The scan runs automatically after a completed run.
            </p>
          </div>
          <p :if={@analysis.osv_scanned_at && @findings == []}>
            No known vulnerabilities in the scanned dependencies.
          </p>

          <div :if={@findings != []} class="pw-table-wrap">
            <table class="pw-table">
              <thead>
                <tr>
                  <th>Package</th>
                  <th>Advisory</th>
                  <th>Severity</th>
                  <th>Fix</th>
                  <th>Tribunal status</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <%= for row <- @finding_rows do %>
                  <tr>
                    <td data-label="Package">
                      <span class="pw-mono">
                        {row.finding.package_name}:{row.finding.package_version}
                      </span>
                      <div :if={row.finding.summary} class="pw-repo-sub">{row.finding.summary}</div>
                      <div :if={via_label(@introduced_via, row.finding)} class="pw-repo-sub">
                        {via_label(@introduced_via, row.finding)}
                      </div>
                    </td>
                    <td data-label="Advisory">
                      <span class="pw-mono">{row.finding.osv_id}</span>
                      <div :for={alias_name <- row.finding.aliases} class="pw-repo-sub">
                        {alias_name}
                      </div>
                    </td>
                    <td data-label="Severity">
                      <span :if={row.finding.severity}>{row.finding.severity}</span>
                      <span :if={!row.finding.severity} class="pw-muted">not reported</span>
                    </td>
                    <td data-label="Fix">
                      {if row.finding.fixed_versions == [],
                        do: "no fix published",
                        else: "fixed in #{Enum.join(row.finding.fixed_versions, ", ")}"}
                    </td>
                    <td data-label="Tribunal status">
                      <%= cond do %>
                        <% row.verdict -> %>
                          <.policy_capped_badge verdict={row.verdict} />
                          <.verdict_badge recommendation={row.verdict.recommendation} />
                        <% MapSet.member?(@queued_case_ids, row.case && row.case.id) -> %>
                          <span class="pw-badge pw-badge--running">Queued</span>
                        <% row.failed -> %>
                          <span class="pw-badge pw-badge--failed">Failed</span>
                        <% row.case -> %>
                          <span class="pw-muted">Not judged</span>
                        <% true -> %>
                          <span class="pw-muted">No dossier yet</span>
                      <% end %>
                    </td>
                    <td>
                      <button
                        type="button"
                        class="pw-expand-button"
                        phx-click="toggle_finding"
                        phx-value-id={row.finding.id}
                      >
                        {if @expanded_finding_id == row.finding.id, do: "Hide", else: "Details"}
                      </button>
                    </td>
                  </tr>
                  <tr :if={@expanded_finding_id == row.finding.id}>
                    <td colspan="6" class="pw-case-cell">
                      <%= cond do %>
                        <% row.verdict -> %>
                          <div class="pw-case-panel">
                            <div :if={row.verdict.policy_capped} class="pw-policy-banner">
                              <strong>POLICY OVERRIDE — HUMAN REVIEW REQUIRED</strong>
                              <span :for={note <- row.verdict.policy_notes}>{note}</span>
                              <span>
                                Judge proposed: {recommendation_label(
                                  row.verdict.judge_recommendation
                                )}
                              </span>
                            </div>

                            <div class="pw-dimension-grid">
                              <div class="pw-dimension">
                                <span>Presence</span><strong>{row.verdict.presence}</strong>
                              </div>
                              <div class="pw-dimension">
                                <span>Application relevance</span>
                                <strong>{row.verdict.application_relevance}</strong>
                              </div>
                              <div class="pw-dimension">
                                <span>Exploitability</span><strong>{row.verdict.exploitability}</strong>
                              </div>
                              <div class="pw-dimension">
                                <span>Priority</span><strong>{row.verdict.priority}</strong>
                              </div>
                              <div class="pw-dimension">
                                <span>Recommendation</span>
                                <strong>{recommendation_label(row.verdict.recommendation)}</strong>
                              </div>
                            </div>

                            <h3>Judge rationale</h3>
                            <p class="pw-rationale">{row.verdict.rationale}</p>

                            <div class="pw-argument-grid">
                              <div
                                :for={role <- ["prosecutor", "defender"]}
                                class="pw-argument-panel"
                              >
                                <h3>{String.capitalize(role)}</h3>
                                <%= cond do %>
                                  <% opinion = latest_opinion(@expanded_opinions, role, "completed") -> %>
                                    <p>{opinion.summary}</p>
                                    <div class="pw-chip-row">
                                      <span
                                        :for={argument <- opinion.arguments}
                                        class="pw-chip-group"
                                      >
                                        <span
                                          :for={evidence_id <- argument["evidence_ids"]}
                                          class="pw-evidence-chip"
                                        >
                                          {evidence_id}
                                        </span>
                                      </span>
                                    </div>
                                    <p :if={opinion.uncertainties != []} class="pw-uncertainties">
                                      Uncertainties: {Enum.join(opinion.uncertainties, "; ")}
                                    </p>
                                  <% opinion = latest_opinion(@expanded_opinions, role, "failed") -> %>
                                    <p class="pw-failed-note">
                                      Opinion failed: {opinion.error}
                                    </p>
                                  <% true -> %>
                                    <p class="pw-muted">No opinion recorded.</p>
                                <% end %>
                              </div>
                            </div>

                            <.case_dossier case={row.case} />
                            <p class="pw-spend">
                              Judge model: {row.verdict.model} · {case_tokens(
                                @expanded_opinions,
                                row.verdict
                              )} tokens measured for this case (advocates + judge)
                            </p>
                          </div>
                        <% row.case -> %>
                          <div class="pw-case-panel">
                            <p :if={row.failed} class="pw-failed-note">
                              The tribunal attempted this case and failed. The failure is
                              recorded on the case; re-running reuses any completed stages.
                            </p>
                            <p :if={!row.failed} class="pw-rationale">
                              Evidence ready. This case has not been argued yet. {triage_reason(
                                row.case
                              )}
                            </p>
                            <button
                              type="button"
                              class="pw-run-button"
                              phx-click="run_tribunal"
                              phx-value-id={row.case.id}
                            >
                              {if row.failed, do: "Re-run tribunal", else: "Run tribunal"}
                            </button>
                            <.case_dossier case={row.case} />
                          </div>
                        <% true -> %>
                          <div class="pw-case-panel">
                            <p class="pw-rationale">
                              No dossier yet — the Investigator has not built a case for this
                              finding. Cases are built automatically after the OSV scan.
                            </p>
                          </div>
                      <% end %>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </section>

        <section
          :if={@analysis.timings != %{} or (@analysis.result && @analysis.result["graph"])}
          class="pw-result"
        >
          <div class="pw-result-head">
            <div>
              <span class="pw-panel-kicker">Instrumentation</span>
              <h2>Stage timings</h2>
            </div>
            <p>Where wall-clock time went, per stage and per module.</p>
          </div>
          <dl class="pw-detail-grid">
            <div :for={{key, value} <- Enum.sort(@analysis.timings)} class="pw-detail-item">
              <dt>{key}</dt>
              <dd class="pw-mono">{value}</dd>
            </div>
            <div
              :if={@analysis.result && @analysis.result["graph"]}
              class="pw-detail-item"
            >
              <dt>Artifacts downloaded</dt>
              <dd class="pw-mono">
                {@analysis.result["graph"]["downloaded_artifacts"]} files, {Float.round(
                  (@analysis.result["graph"]["downloaded_bytes"] || 0) / 1_000_000,
                  1
                )} MB
              </dd>
            </div>
          </dl>
          <ul
            :if={@analysis.result && @analysis.result["graph"]}
            class="pw-analysis-list"
          >
            <li
              :for={mod <- @analysis.result["graph"]["modules"] || []}
              class="pw-analysis-row"
            >
              <span class="pw-mono">{mod["module"] || mod["pom_path"]}</span>
              <div class="pw-meta">
                <span>{mod["status"]}</span>
                <span>{mod["duration_ms"]} ms</span>
                <span>{mod["dependencies"]} dependencies</span>
                <span>{mod["pom_path"]}</span>
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
