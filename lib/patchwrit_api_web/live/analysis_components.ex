defmodule PatchwritApiWeb.AnalysisComponents do
  @moduledoc "Shared rendering helpers for analysis status display."

  use Phoenix.Component

  attr :status, :string, required: true

  def status_badge(assigns) do
    ~H"""
    <span class={["inline-block rounded px-2 py-0.5 text-xs font-semibold", status_class(@status)]}>
      {@status}
    </span>
    """
  end

  attr :status, :string, required: true

  def cleanup_badge(assigns) do
    ~H"""
    <span class={["inline-block rounded px-2 py-0.5 text-xs font-semibold", cleanup_class(@status)]}>
      cleanup: {@status}
    </span>
    """
  end

  defp status_class("completed"), do: "bg-emerald-100 text-emerald-900"
  defp status_class("failed"), do: "bg-red-100 text-red-900"
  defp status_class("cancelled"), do: "bg-zinc-200 text-zinc-800"
  defp status_class("running"), do: "bg-sky-100 text-sky-900"
  defp status_class("provisioning"), do: "bg-amber-100 text-amber-900"
  defp status_class(_), do: "bg-zinc-100 text-zinc-800"

  defp cleanup_class("destroyed"), do: "bg-emerald-100 text-emerald-900"
  defp cleanup_class("failed"), do: "bg-red-100 text-red-900"
  defp cleanup_class(_), do: "bg-amber-100 text-amber-900"
end
