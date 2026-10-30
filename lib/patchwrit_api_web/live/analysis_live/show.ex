defmodule PatchwritApiWeb.AnalysisLive.Show do
  @moduledoc "Detail view for one persisted Analysis."

  use PatchwritApiWeb, :live_view

  alias PatchwritApi.Analyses
  alias PatchwritApi.Analyses.DependencyGraph
  alias PatchwritApi.Findings
  import PatchwritApiWeb.AnalysisComponents

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    analysis = Analyses.get_analysis!(id)
    findings = Findings.list_findings_for_analysis(analysis.id)
    dependencies = get_in(analysis.result || %{}, ["dependencies"]) || []
    dep_modules = DependencyGraph.modules(dependencies)

    {:ok,
     socket
     |> assign(:analysis, analysis)
     |> assign(:findings, findings)
     |> assign(:dep_rows, DependencyGraph.aggregate(dependencies))
     |> assign(:dep_modules, dep_modules)
     |> assign(:deps_module, List.first(dep_modules))
     |> assign(:deps_view, "table")
     |> assign(:deps_direct_only, false)
     |> assign(:expanded_dep, nil)
     |> assign(:deps_query, "")
     |> assign(:deps_limit, 25)
     |> assign(
       :vulnerable_coords,
       MapSet.new(findings, &"#{&1.package_name}:#{&1.package_version}")
     )
     |> assign(:introduced_via, introduced_via_map(analysis))}
  end

  @impl true
  def handle_event("set_deps_view", %{"view" => view}, socket)
      when view in ~w(table tree) do
    {:noreply, assign(socket, deps_view: view, deps_limit: 25)}
  end

  def handle_event("toggle_dep", %{"coordinate" => coordinate}, socket) do
    expanded = if socket.assigns.expanded_dep == coordinate, do: nil, else: coordinate
    {:noreply, assign(socket, expanded_dep: expanded)}
  end

  def handle_event("toggle_direct_only", _params, socket) do
    {:noreply, assign(socket, deps_direct_only: !socket.assigns.deps_direct_only, deps_limit: 25)}
  end

  def handle_event("deps_search", %{"query" => query}, socket) do
    {:noreply, assign(socket, deps_query: query, deps_limit: 25)}
  end

  def handle_event("more_deps", _params, socket) do
    {:noreply, assign(socket, deps_limit: socket.assigns.deps_limit + 50)}
  end

  def handle_event("select_deps_module", %{"module" => module}, socket) do
    {:noreply, assign(socket, deps_module: module)}
  end

  # Essential table only: vulnerable first, then A-Z. Everything else
  # about a dependency lives in its expanded detail, not in columns.
  defp visible_dep_rows(assigns) do
    rows =
      assigns.dep_rows
      |> Enum.filter(&(&1.min_depth >= 1))
      |> Enum.sort_by(fn row ->
        {if(MapSet.member?(assigns.vulnerable_coords, row.coordinate), do: 0, else: 1),
         row.coordinate}
      end)

    rows =
      if assigns.deps_direct_only,
        do: Enum.filter(rows, & &1.direct),
        else: rows

    query = String.downcase(String.trim(assigns.deps_query))

    if query == "" do
      rows
    else
      Enum.filter(rows, &String.contains?(String.downcase(&1.coordinate), query))
    end
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

  attr :rows, :list, required: true
  attr :vulnerable, :any, required: true
  attr :expanded, :string, default: nil

  # Essential columns only: what it is, its scope, whether it is a
  # finding. Depth/modules/paths live in the expanded detail.
  defp deps_table(assigns) do
    ~H"""
    <div class="pw-table-wrap">
      <table class="pw-table">
        <thead>
          <tr>
            <th>Dependency</th>
            <th>Scope</th>
            <th>Status</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          <%= for row <- @rows do %>
            <tr>
              <td data-label="Dependency">
                <span class="pw-mono">{row.coordinate}</span>
                <span :if={row.direct} class="pw-badge pw-verdict--investigate">Direct</span>
              </td>
              <td data-label="Scope">{Enum.join(row.scopes, ", ")}</td>
              <td data-label="Status">
                <span
                  :if={MapSet.member?(@vulnerable, row.coordinate)}
                  class="pw-badge pw-verdict--remediate"
                >
                  Vulnerable
                </span>
                <span :if={!MapSet.member?(@vulnerable, row.coordinate)} class="pw-muted">—</span>
              </td>
              <td>
                <button
                  type="button"
                  class="pw-expand-button"
                  phx-click="toggle_dep"
                  phx-value-coordinate={row.coordinate}
                >
                  {if @expanded == row.coordinate, do: "Hide", else: "Details"}
                </button>
              </td>
            </tr>
            <tr :if={@expanded == row.coordinate}>
              <td colspan="4" class="pw-case-cell">
                <div class="pw-dep-detail">
                  <p>
                    Depth {row.min_depth} (1 = declared directly in a POM)<span :if={
                      row.module_count > 0
                    }>
                      · appears in {row.module_count} module(s)</span>
                    <span>
                      · reached by {row.path_count} introduction path(s)
                    </span>
                    <span>
                      · {row.downstream} dependencies sit beneath it
                    </span>
                  </p>
                  <p :if={row.paths != []} class="pw-mono pw-dep-paths">
                    <span :for={path <- Enum.take(row.paths, 5)}>
                      {Enum.join(path, " → ")}<br />
                    </span>
                    <span :if={length(row.paths) > 5}>…and {length(row.paths) - 5} more paths</span>
                  </p>
                </div>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  attr :nodes, :list, required: true
  attr :vulnerable, :any, required: true
  attr :depth, :integer, default: 0

  defp deps_tree(assigns) do
    ~H"""
    <ul class="pw-tree">
      <li :for={{name, children} <- @nodes}>
        <details :if={children != []} open={@depth == 0}>
          <summary>
            <span class="pw-mono">{name}</span>
            <span :if={MapSet.member?(@vulnerable, name)} class="pw-badge pw-verdict--remediate">
              Vulnerable
            </span>
          </summary>
          <.deps_tree nodes={children} vulnerable={@vulnerable} depth={@depth + 1} />
        </details>
        <span :if={children == []}>
          <span class="pw-mono">{name}</span>
          <span :if={MapSet.member?(@vulnerable, name)} class="pw-badge pw-verdict--remediate">
            Vulnerable
          </span>
        </span>
      </li>
    </ul>
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
              <h2>Dependencies ({length(@dep_rows)} unique)</h2>
            </div>
            <p>
              {length(@analysis.result["dependencies"])} resolved entries across {length(@dep_modules)} modules. Impact = module spread and introduction-path fan-in (build-graph
              structure, not runtime usage).
            </p>
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

          <div class="pw-deps-controls">
            <div class="pw-tabs" role="tablist" aria-label="Dependency views">
              <button
                :for={
                  {view, label} <- [
                    {"table", "Table"},
                    {"tree", "Tree"}
                  ]
                }
                type="button"
                class={["pw-tab", @deps_view == view && "pw-tab--active"]}
                phx-click="set_deps_view"
                phx-value-view={view}
              >
                {label}
              </button>
            </div>
            <button
              :if={@deps_view != "tree"}
              type="button"
              class={["pw-tab", @deps_direct_only && "pw-tab--active"]}
              phx-click="toggle_direct_only"
              aria-pressed={@deps_direct_only}
            >
              Direct only
            </button>
            <form phx-change="deps_search" class="pw-deps-search">
              <input
                type="text"
                name="query"
                value={@deps_query}
                placeholder="Filter by coordinate…"
                phx-debounce="200"
              />
            </form>
          </div>

          <p class="pw-view-note">
            <%= if @deps_view == "tree" do %>
              Introduction chains for one module, in dependency:tree style.
            <% else %>
              Every unique dependency, vulnerable first. Details hold depth, modules, and
              the introduction paths behind each row.
            <% end %>
          </p>

          <%= if @deps_view == "tree" do %>
            <div :if={length(@dep_modules) > 1} class="pw-module-chips">
              <button
                :for={module <- @dep_modules}
                type="button"
                class={["pw-tab", @deps_module == module && "pw-tab--active"]}
                phx-click="select_deps_module"
                phx-value-module={module}
              >
                {module}
              </button>
            </div>
            <.deps_tree
              nodes={DependencyGraph.tree(@analysis.result["dependencies"], @deps_module)}
              vulnerable={@vulnerable_coords}
            />
          <% else %>
            <% rows = visible_dep_rows(assigns) %>
            <p class="pw-count">
              Showing {min(@deps_limit, length(rows))} of {length(rows)} unique dependencies
            </p>
            <.deps_table
              rows={Enum.take(rows, @deps_limit)}
              vulnerable={@vulnerable_coords}
              expanded={@expanded_dep}
            />
            <button
              :if={length(rows) > @deps_limit}
              type="button"
              class="pw-expand-button"
              phx-click="more_deps"
            >
              Show more
            </button>
          <% end %>
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
