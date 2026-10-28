defmodule PatchwritApi.LogTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias PatchwritApi.Log

  test "formats a stable sorted key=value event" do
    line =
      Log.format("analysis.completed", %{
        status: "completed",
        analysis_id: "abc-123",
        duration_ms: 42,
        graph_complete: true
      })

    assert line ==
             "patchwrit event=analysis.completed analysis_id=abc-123 duration_ms=42 graph_complete=true status=completed"
  end

  test "quotes values that are not log-safe" do
    assert Log.format("scan.failed", %{error: "OSV API returned 503"}) ==
             ~s(patchwrit event=scan.failed error="OSV API returned 503")
  end

  test "warning events reach the Logger" do
    assert capture_log([level: :warning], fn ->
             Log.warning("callback.rejected", %{analysis_id: "abc-123", reason: "unauthorized"})
           end) =~ "patchwrit event=callback.rejected"
  end
end
