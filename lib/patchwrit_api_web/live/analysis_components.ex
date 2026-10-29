defmodule PatchwritApiWeb.AnalysisComponents do
  @moduledoc "Shared rendering helpers for analysis status display."

  use Phoenix.Component

  import PatchwritApiWeb.CoreComponents

  attr :active, :string, default: "docket"

  @doc """
  App sidebar: brand and primary nav only. Rendered by every console
  page so the product reads as one full-screen application. Page
  content (stats, actions) belongs in the page, never in the menu.
  """
  def app_sidebar(assigns) do
    ~H"""
    <aside class="pw-sidebar">
      <a href="/analyses" class="pw-sidebar-brand">
        <span class="pw-mark">PW</span>
        <span class="pw-brand-copy">
          <strong>Patchwrit</strong>
          <span>Analysis console</span>
        </span>
      </a>

      <nav class="pw-sidebar-nav" aria-label="Primary">
        <a
          href="/analyses"
          class={["pw-nav-item", @active == "docket" && "pw-nav-item--active"]}
        >
          Docket
        </a>
        <a
          href="/repositories"
          class={["pw-nav-item", @active == "repositories" && "pw-nav-item--active"]}
        >
          Repositories
        </a>
        <a href="/analyses#recent-analyses-title" class="pw-nav-item">Analyses</a>
        <span :if={@active == "analysis"} class="pw-nav-item pw-nav-item--active">
          Analysis detail
        </span>
      </nav>
    </aside>
    """
  end

  # -- repository setup panel (shared by the docket and repositories page) -----

  attr :repository_form, :any, required: true
  attr :branch_options, :list, required: true
  attr :branch_state, :atom, required: true
  attr :branch_error, :string, required: true

  @doc "Track-a-repository form panel (branch fetch is handled by the LiveView)."
  def repository_setup(assigns) do
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
        <button type="submit" class="pw-submit">Track Repository</button>
      </.form>
    </section>
    """
  end

  attr :status, :string, required: true

  def status_badge(assigns) do
    ~H"""
    <span class={["pw-badge", badge_class(@status)]}>{@status}</span>
    """
  end

  attr :status, :string, required: true

  def cleanup_badge(assigns) do
    ~H"""
    <span class={["pw-badge", badge_class(@status)]}>cleanup: {@status}</span>
    """
  end

  @recommendation_labels %{
    "remediate_now" => "Remediate now",
    "schedule_remediation" => "Schedule remediation",
    "investigate_usage" => "Investigate usage",
    "needs_human_review" => "Needs human review",
    "dismiss" => "Dismiss"
  }

  @doc "Human label for a tribunal recommendation value."
  def recommendation_label(recommendation) do
    Map.get(@recommendation_labels, recommendation, recommendation || "Unknown")
  end

  attr :recommendation, :string, required: true

  def verdict_badge(assigns) do
    ~H"""
    <span class={["pw-badge", "pw-verdict-badge", verdict_class(@recommendation)]}>
      {recommendation_label(@recommendation)}
    </span>
    """
  end

  attr :verdict, :map, required: true

  @doc "The dark policy-cap marker: louder than the verdict it overruled."
  def policy_capped_badge(assigns) do
    ~H"""
    <span :if={@verdict.policy_capped} class="pw-badge pw-policy-badge">
      Policy: human review
    </span>
    """
  end

  defp verdict_class("remediate_now"), do: "pw-verdict--remediate"
  defp verdict_class("schedule_remediation"), do: "pw-verdict--schedule"
  defp verdict_class("investigate_usage"), do: "pw-verdict--investigate"
  defp verdict_class("needs_human_review"), do: "pw-verdict--review"
  defp verdict_class("dismiss"), do: "pw-verdict--dismiss"
  defp verdict_class(_other), do: "pw-verdict--review"

  defp badge_class(status) when status in ~w(completed destroyed), do: "pw-badge--#{status}"

  defp badge_class(status)
       when status in ~w(failed provisioning pending running cancelled queued),
       do: "pw-badge--#{status}"

  defp badge_class(_status), do: "pw-badge--queued"
end
