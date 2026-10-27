defmodule PatchwritApiWeb.AnalysisLive.Index do
  @moduledoc """
  Track repositories and run persisted analyses from one page.

  Entering a valid public GitHub URL fetches its branches immediately so
  the user can choose a non-default branch. The Java version is manual:
  the user who tracks the repository specifies the JDK it should use.
  """

  use PatchwritApiWeb, :live_view

  alias PatchwritApi.Analyses
  alias PatchwritApi.GitHub
  alias PatchwritApi.Repositories
  alias PatchwritApi.Repositories.Repository
  import PatchwritApiWeb.AnalysisComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:repositories, Repositories.list_repositories())
     |> assign(:analyses, Analyses.list_analyses())
     |> assign(:branch_options, [])
     |> assign(:branches_for_url, nil)
     |> assign(:branch_state, :idle)
     |> assign(:branch_error, nil)
     |> assign_repository_form(%{})}
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
         |> assign(:repositories, Repositories.list_repositories())
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
         |> assign(:analyses, Analyses.list_analyses())}

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

      <div class="pw-page-head">
        <h1>Tracked repositories</h1>
        <p>
          Track a public GitHub Maven repository, choose the branch to analyze, and specify the Java version its worker should use.
        </p>
      </div>

      <div class="pw-layout">
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

        <div>
          <section aria-labelledby="tracked-repositories-title">
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
                  <%= if latest = latest_analysis(@analyses, repository) do %>
                    <.status_badge status={latest.status} />
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

          <section class="pw-recent-section" aria-labelledby="recent-analyses-title">
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
                </div>
              </li>
            </ul>
          </section>
        </div>
      </div>
    </div>
    """
  end
end
