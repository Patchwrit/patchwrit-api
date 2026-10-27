defmodule PatchwritApiWeb.AnalysisLive.Index do
  @moduledoc """
  Submit a repository for analysis and watch persisted analyses.

  Submission creates an Analysis and enqueues its Fly worker dispatch.
  """

  use PatchwritApiWeb, :live_view

  alias PatchwritApi.Analyses
  alias PatchwritApi.Analyses.Analysis
  import PatchwritApiWeb.AnalysisComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:analyses, Analyses.list_analyses())
     |> assign_form(%{})}
  end

  @impl true
  def handle_event("validate", %{"analysis" => params}, socket) do
    changeset =
      %Analysis{}
      |> Analysis.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"analysis" => params}, socket) do
    case Analyses.create_analysis(params) do
      {:ok, analysis} ->
        PatchwritApi.Workers.DispatchAnalysis.enqueue(analysis)

        {:noreply,
         socket
         |> put_flash(:info, "Analysis queued")
         |> assign(:analyses, Analyses.list_analyses())
         |> assign_form(%{})}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp assign_form(socket, attrs) do
    changeset = Analysis.changeset(%Analysis{}, attrs)
    assign(socket, :form, to_form(changeset))
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
        <h1>Repository analyses</h1>
        <p>
          Queue a public GitHub repository, pin the selected ref to a commit, and follow the worker through provisioning, execution, callback, and cleanup.
        </p>
      </div>

      <div class="pw-layout">
        <section class="pw-panel" aria-labelledby="new-analysis-title">
          <span class="pw-panel-kicker">New run</span>
          <h2 id="new-analysis-title">Start an analysis</h2>
          <p class="pw-panel-copy">
            The repository is analyzed in a disposable worker. Nothing runs on this host.
          </p>

          <.form
            for={@form}
            id="analysis-form"
            phx-change="validate"
            phx-submit="save"
            class="pw-form"
          >
            <.input
              field={@form[:repository_url]}
              label="Repository URL"
              placeholder="https://github.com/owner/repo"
            />
            <.input
              field={@form[:requested_ref]}
              label="Ref (branch, tag, or SHA)"
              placeholder="HEAD"
            />
            <button type="submit" class="pw-submit">Queue analysis</button>
          </.form>
        </section>

        <section aria-labelledby="recent-analyses-title">
          <div class="pw-section-head">
            <div>
              <span class="pw-panel-kicker">Queue</span>
              <h2 id="recent-analyses-title">Recent analyses</h2>
            </div>
            <span class="pw-count">{length(@analyses)} total</span>
          </div>

          <div :if={@analyses == []} class="pw-empty">
            <strong>No analyses yet</strong>
            Start the first run from the form and it will appear here.
          </div>

          <ul :if={@analyses != []} class="pw-analysis-list">
            <li :for={analysis <- @analyses} class="pw-analysis-row">
              <.link navigate={~p"/analyses/#{analysis.id}"} class="pw-repo-link">
                {analysis.repository_url}
              </.link>
              <div class="pw-meta">
                <span>ref: <span class="pw-mono">{analysis.requested_ref}</span></span>
                <.status_badge status={analysis.status} />
                <.cleanup_badge status={analysis.machine_cleanup_status} />
              </div>
            </li>
          </ul>
        </section>
      </div>
    </div>
    """
  end
end
