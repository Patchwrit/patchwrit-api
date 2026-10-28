defmodule PatchwritApi.Log do
  @moduledoc """
  Shared structured application events.

  Phoenix and the Go worker emit the same one-line event vocabulary
  (see docs/LOGGING.md):

      patchwrit event=analysis.completed analysis_id=<id> status=completed duration_ms=123

  Fields are sorted for stable, greppable output. Never pass tokens,
  authorization headers, full callback payloads, or model prompts.
  """

  require Logger

  @safe_value ~r/\A[A-Za-z0-9_:\.\-\/]+\z/

  def info(event, fields \\ %{}), do: emit(:info, event, fields)
  def warning(event, fields \\ %{}), do: emit(:warning, event, fields)
  def error(event, fields \\ %{}), do: emit(:error, event, fields)

  defp emit(level, event, fields) do
    Logger.log(level, format(event, fields))
  end

  @doc "Formats one event line; exposed for tests and documentation."
  def format(event, fields) do
    rendered =
      fields
      |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
      |> Enum.map(fn {key, value} -> " #{key}=#{format_value(value)}" end)

    "patchwrit event=#{event}#{rendered}"
  end

  defp format_value(nil), do: "nil"
  defp format_value(value) when is_boolean(value) or is_number(value), do: to_string(value)
  defp format_value(value) when is_atom(value), do: Atom.to_string(value)

  defp format_value(value) when is_binary(value) do
    if Regex.match?(@safe_value, value), do: value, else: Jason.encode!(value)
  end

  defp format_value(value), do: Jason.encode!(value)
end
