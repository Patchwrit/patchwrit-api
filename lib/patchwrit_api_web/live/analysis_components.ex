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
      <div class="pw-sidebar-head">
        <a href="/analyses" class="pw-sidebar-brand">
          <span class="pw-mark">PW</span>
          <span class="pw-brand-copy">
            <strong>Patchwrit</strong>
            <span>Analysis console</span>
          </span>
        </a>
        <button
          type="button"
          class="pw-sidebar-toggle"
          data-pw-sidebar-toggle
          aria-label="Collapse or expand sidebar"
          title="Collapse or expand sidebar"
        >
          <.nav_icon name="chevron" class="pw-toggle-icon" />
        </button>
      </div>

      <nav class="pw-sidebar-nav" aria-label="Primary">
        <a
          href="/analyses"
          title="Docket"
          class={["pw-nav-item", @active == "docket" && "pw-nav-item--active"]}
        >
          <.nav_icon name="docket" />
          <span class="pw-nav-label">Docket</span>
        </a>
        <a
          href="/repositories"
          title="Repositories"
          class={["pw-nav-item", @active == "repositories" && "pw-nav-item--active"]}
        >
          <.nav_icon name="repositories" />
          <span class="pw-nav-label">Repositories</span>
        </a>
        <a href="/analyses#recent-analyses-title" title="Analyses" class="pw-nav-item">
          <.nav_icon name="analyses" />
          <span class="pw-nav-label">Analyses</span>
        </a>
        <span
          :if={@active == "analysis"}
          title="Analysis detail"
          class="pw-nav-item pw-nav-item--active"
        >
          <.nav_icon name="detail" />
          <span class="pw-nav-label">Analysis detail</span>
        </span>
      </nav>
    </aside>
    """
  end

  attr :name, :string, required: true
  attr :class, :string, default: "pw-nav-icon"

  @doc """
  Inline Heroicon (MIT) for sidebar navigation. Inlined on purpose:
  the Tailwind heroicons plugin only emits these when the asset build
  runs, and a stale build silently produced empty icon slots. Same
  24px outline path data as `deps/heroicons`.
  """
  def nav_icon(assigns) do
    ~H"""
    <svg
      class={@class}
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      stroke-width="1.5"
      stroke="currentColor"
      aria-hidden="true"
    >
      <path stroke-linecap="round" stroke-linejoin="round" d={nav_icon_path(@name)} />
    </svg>
    """
  end

  defp nav_icon_path("chevron"), do: "M15.75 19.5 8.25 12l7.5-7.5"

  defp nav_icon_path("docket"),
    do:
      "M3.75 6A2.25 2.25 0 0 1 6 3.75h2.25A2.25 2.25 0 0 1 10.5 6v2.25a2.25 2.25 0 0 1-2.25 2.25H6a2.25 2.25 0 0 1-2.25-2.25V6ZM3.75 15.75A2.25 2.25 0 0 1 6 13.5h2.25a2.25 2.25 0 0 1 2.25 2.25V18a2.25 2.25 0 0 1-2.25 2.25H6A2.25 2.25 0 0 1 3.75 18v-2.25ZM13.5 6a2.25 2.25 0 0 1 2.25-2.25H18A2.25 2.25 0 0 1 20.25 6v2.25A2.25 2.25 0 0 1 18 10.5h-2.25a2.25 2.25 0 0 1-2.25-2.25V6ZM13.5 15.75a2.25 2.25 0 0 1 2.25-2.25H18a2.25 2.25 0 0 1 2.25 2.25V18A2.25 2.25 0 0 1 18 20.25h-2.25A2.25 2.25 0 0 1 13.5 18v-2.25Z"

  defp nav_icon_path("repositories"),
    do:
      "M2.25 12.75V12A2.25 2.25 0 0 1 4.5 9.75h15A2.25 2.25 0 0 1 21.75 12v.75m-8.69-6.44-2.12-2.12a1.5 1.5 0 0 0-1.061-.44H4.5A2.25 2.25 0 0 0 2.25 6v12a2.25 2.25 0 0 0 2.25 2.25h15A2.25 2.25 0 0 0 21.75 18V9a2.25 2.25 0 0 0-2.25-2.25h-5.379a1.5 1.5 0 0 1-1.06-.44Z"

  defp nav_icon_path("analyses"), do: "M12 6v6h4.5m4.5 0a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z"

  defp nav_icon_path("detail"),
    do:
      "M19.5 14.25v-2.625a3.375 3.375 0 0 0-3.375-3.375h-1.5A1.125 1.125 0 0 1 13.5 7.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H8.25m5.231 13.481L15 17.25m-4.5-15H5.625c-.621 0-1.125.504-1.125 1.125v16.5c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 0 0-9-9Zm3.75 11.625a2.625 2.625 0 1 1-5.25 0 2.625 2.625 0 0 1 5.25 0Z"

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

  @doc "A discreet note that policy capped this verdict; detail lives on the case page."
  def policy_capped_badge(assigns) do
    ~H"""
    <span :if={@verdict.policy_capped} class="pw-policy-note">policy-capped</span>
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
