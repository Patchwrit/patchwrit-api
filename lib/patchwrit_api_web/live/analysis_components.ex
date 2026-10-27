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

  defp badge_class(status) when status in ~w(completed destroyed), do: "pw-badge--#{status}"

  defp badge_class(status)
       when status in ~w(failed provisioning pending running cancelled queued),
       do: "pw-badge--#{status}"

  defp badge_class(_status), do: "pw-badge--queued"
end
