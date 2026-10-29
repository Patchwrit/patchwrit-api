defmodule PatchwritApiWeb.AnalysisComponents do
  @moduledoc "Shared rendering helpers for analysis status display."

  use Phoenix.Component

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
