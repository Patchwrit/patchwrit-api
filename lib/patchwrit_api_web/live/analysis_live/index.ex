defmodule PatchwritApiWeb.AnalysisLive.Index do
  @moduledoc """
  Submit a repository for analysis and watch persisted analyses.

  W4 scope: submission only creates a `queued` Analysis. Dispatch to a
  Fly worker arrives in W5; nothing here talks to Fly.
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
      {:ok, _analysis} ->
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
    <div class="mx-auto max-w-3xl px-4 py-8">
      <h1 class="text-2xl font-bold text-zinc-900">Analyses</h1>

      <section class="mt-6 rounded border border-zinc-200 p-4">
        <h2 class="text-base font-semibold text-zinc-900">New analysis</h2>
        <.form
          for={@form}
          id="analysis-form"
          phx-change="validate"
          phx-submit="save"
          class="mt-3 space-y-3"
        >
          <.input
            field={@form[:repository_url]}
            label="Repository URL"
            placeholder="https://github.com/owner/repo"
          />
          <.input field={@form[:requested_ref]} label="Ref (branch, tag, or SHA)" placeholder="HEAD" />
          <button type="submit" class="rounded bg-zinc-900 px-4 py-2 text-sm font-semibold text-white">
            Queue analysis
          </button>
        </.form>
      </section>

      <section class="mt-8">
        <p :if={@analyses == []} class="text-sm text-zinc-600">No analyses yet</p>
        <ul class="divide-y divide-zinc-200">
          <li :for={analysis <- @analyses} class="py-3">
            <.link navigate={~p"/analyses/#{analysis.id}"} class="font-medium text-zinc-900 underline">
              {analysis.repository_url}
            </.link>
            <div class="mt-1 flex items-center gap-2 text-sm text-zinc-600">
              <span>ref: {analysis.requested_ref}</span>
              <.status_badge status={analysis.status} />
              <.cleanup_badge status={analysis.machine_cleanup_status} />
            </div>
          </li>
        </ul>
      </section>
    </div>
    """
  end
end
