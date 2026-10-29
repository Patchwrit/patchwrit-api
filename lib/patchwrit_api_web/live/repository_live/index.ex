defmodule PatchwritApiWeb.RepositoryLive.Index do
  @moduledoc """
  The repository library: every tracked repository with its latest
  known risk posture, one comparable row each.

  Posture comes from persisted analyses and tribunal verdicts via
  `PatchwritApiWeb.RepoPosture`; failed newer runs never erase the
  last known posture. Tracking a repository (with on-the-spot GitHub
  branch fetching and manual JDK choice) also lives here.
  """

  use PatchwritApiWeb, :live_view

  alias PatchwritApi.Analyses
  alias PatchwritApi.GitHub
  alias PatchwritApi.Repositories
  alias PatchwritApi.Repositories.Repository
  alias PatchwritApiWeb.RepoPosture
  import PatchwritApiWeb.AnalysisComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign_library()
     |> assign(:branch_options, [])
     |> assign(:branches_for_url, nil)
     |> assign(:branch_state, :idle)
     |> assign(:branch_error, nil)
     |> assign_repository_form(%{})}
  end

  defp assign_library(socket) do
    repositories = Repositories.list_repositories()
    analyses = Analyses.list_analyses()
    postures = RepoPosture.postures(repositories, analyses)

    rows =
      repositories
      |> Enum.map(&{&1, postures[&1.id]})
      |> Enum.sort_by(fn {repository, posture} ->
        {-(Map.get(posture, :attention) || 0), repository.repository_url}
      end)

    socket
    |> assign(:repositories, repositories)
    |> assign(:rows, rows)
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
    params =
      if name = socket.assigns[:fetched_repo_name],
        do: Map.put(params, "name", name),
        else: params

    case Repositories.create_repository(params) do
      {:ok, _repository} ->
        {:noreply,
         socket
         |> put_flash(:info, "Repository tracked")
         |> assign_library()
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
         |> assign_library()}

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
          {:ok, %{default_branch: default_branch, branches: branches} = fetched} ->
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
             |> assign(:fetched_repo_name, fetched.name)
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

  defp clean_scan?(posture) do
    posture.latest && posture.latest.osv_scanned_at && posture.findings == 0
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="pw-app">
      <.app_sidebar active="repositories" />

      <main class="pw-main">
        <div class="pw-docket-head">
          <div>
            <h1>Repositories</h1>
            <p>
              Every tracked repository with its latest known risk posture—worst first, failures never hidden.
            </p>
          </div>
          <a href="#track-repository-title" class="pw-track-cta">+ Track Repository</a>
        </div>

        <section aria-labelledby="repositories-table-title">
          <div class="pw-section-head">
            <div>
              <span class="pw-panel-kicker">Library</span>
              <h2 id="repositories-table-title">Tracked repositories</h2>
            </div>
            <span class="pw-count">{length(@repositories)} tracked</span>
          </div>

          <div :if={@repositories == []} class="pw-empty">
            <strong>No tracked repositories yet</strong>
            Add one from the form below and it will be ready to run.
          </div>

          <div :if={@repositories != []} class="pw-table-wrap">
            <table class="pw-table">
              <thead>
                <tr>
                  <th>Repository</th>
                  <th>Worst verdict</th>
                  <th>Attention</th>
                  <th>Findings</th>
                  <th>Coverage</th>
                  <th>Latest run</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={{repository, posture} <- @rows}>
                  <td data-label="Repository">
                    <.link
                      :if={posture.latest}
                      navigate={~p"/analyses/#{posture.latest.id}"}
                      class="pw-repo-link"
                    >
                      {Repository.display_name(repository)}
                    </.link>
                    <span :if={!posture.latest} class="pw-repo-link">
                      {Repository.display_name(repository)}
                    </span>
                    <div class="pw-repo-sub">
                      {repository.default_ref} · JDK {repository.java_version}<span :if={
                        posture.latest && posture.latest.resolved_sha
                      }>
                        · {String.slice(posture.latest.resolved_sha, 0, 7)}
                      </span>
                    </div>
                  </td>
                  <td data-label="Worst verdict">
                    <.verdict_badge :if={posture.worst} recommendation={posture.worst} />
                    <span :if={!posture.worst && clean_scan?(posture)} class="pw-clean-note">
                      Clean scan
                    </span>
                    <span :if={!posture.worst && !clean_scan?(posture)} class="pw-muted">
                      Not judged
                    </span>
                  </td>
                  <td data-label="Attention">
                    <span :if={posture.latest && posture.attention > 0} class="pw-attention-count">
                      {posture.attention}
                    </span>
                    <span :if={posture.latest && posture.attention == 0} class="pw-muted">0</span>
                    <span :if={!posture.latest} class="pw-muted">—</span>
                  </td>
                  <td data-label="Findings">
                    <span :if={posture.latest}>{posture.findings}</span>
                    <span :if={!posture.latest} class="pw-muted">—</span>
                  </td>
                  <td data-label="Coverage">
                    <span :if={posture.latest}>{posture.coverage}</span>
                    <span :if={!posture.latest} class="pw-muted">Not yet evaluated</span>
                  </td>
                  <td data-label="Latest run">
                    <%= if posture.latest do %>
                      <.status_badge status={posture.latest.status} />
                      <div class="pw-repo-sub">{posture.evaluated}</div>
                    <% else %>
                      <span class="pw-muted">No runs yet</span>
                    <% end %>
                  </td>
                  <td data-label="Actions">
                    <button
                      id={"run-repository-#{repository.id}"}
                      type="button"
                      class="pw-run-button"
                      phx-click="run_repository"
                      phx-value-id={repository.id}
                    >
                      Run analysis
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <section class="pw-dashboard-section" aria-label="Repository setup">
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
