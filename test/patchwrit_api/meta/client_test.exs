defmodule PatchwritApi.Meta.ClientTest do
  use ExUnit.Case, async: false

  alias PatchwritApi.Meta.Client

  @stub PatchwritApi.MetaStub

  setup do
    Req.Test.set_req_test_to_shared()
    previous = Application.get_env(:patchwrit_api, :meta)

    Application.put_env(:patchwrit_api, :meta,
      api_key: "test-key",
      base_url: "https://api.meta.ai/v1",
      req_options: [plug: {Req.Test, @stub}]
    )

    on_exit(fn ->
      if previous,
        do: Application.put_env(:patchwrit_api, :meta, previous),
        else: Application.delete_env(:patchwrit_api, :meta)
    end)

    :ok
  end

  defp responses_json(conn, text, usage \\ %{}) do
    Req.Test.json(conn, %{
      "model" => "muse-spark-1.3",
      "output" => [
        %{
          "type" => "message",
          "role" => "assistant",
          "content" => [%{"type" => "output_text", "text" => text}]
        }
      ],
      "usage" => usage
    })
  end

  test "sends a Responses request with Bearer [REDACTED] and returns content + normalized usage" do
    parent = self()

    Req.Test.stub(@stub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(parent, {:meta_request, conn, Jason.decode!(body)})

      responses_json(conn, "pong", %{
        "input_tokens" => 100,
        "output_tokens" => 6,
        "total_tokens" => 106,
        "input_tokens_details" => %{"cached_tokens" => 80},
        "output_tokens_details" => %{"reasoning_tokens" => 4}
      })
    end)

    assert {:ok, result} =
             Client.complete(
               [
                 %{"role" => "system", "content" => "Be terse."},
                 %{"role" => "user", "content" => "ping"}
               ],
               prompt_cache_key: "case:abc"
             )

    assert result.content == "pong"
    assert result.model == "muse-spark-1.3"
    # Responses usage is normalized to the persisted tribunal shape,
    # including the cache-hit count.
    assert result.usage["prompt_tokens"] == 100
    assert result.usage["completion_tokens"] == 6
    assert result.usage["total_tokens"] == 106
    assert result.usage["prompt_tokens_details"]["cached_tokens"] == 80
    assert result.usage["completion_tokens_details"]["reasoning_tokens"] == 4

    assert_received {:meta_request, conn, payload}
    assert conn.request_path == "/v1/responses"
    assert ["Bearer " <> _key] = Plug.Conn.get_req_header(conn, "authorization")
    assert payload["model"] == "muse-spark-1.3"
    assert payload["instructions"] == "Be terse."
    assert payload["input"] == [%{"role" => "user", "content" => "ping"}]
    assert payload["prompt_cache_key"] == "case:abc"
    assert payload["prompt_cache_retention"] == "in_memory"
  end

  test "explicit model option wins (judge model)" do
    Req.Test.stub(@stub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert Jason.decode!(body)["model"] == "muse-wonder-1.0"

      responses_json(conn, "judged")
    end)

    assert {:ok, %{content: "judged"}} =
             Client.complete([%{role: "user", content: "case"}], model: Client.judge_model())
  end

  test "reasoning items in the output are skipped for the message text" do
    Req.Test.stub(@stub, fn conn ->
      Req.Test.json(conn, %{
        "output" => [
          %{"type" => "reasoning", "summary" => []},
          %{
            "type" => "message",
            "content" => [%{"type" => "output_text", "text" => "verdict"}]
          }
        ]
      })
    end)

    assert {:ok, %{content: "verdict"}} = Client.complete([%{"role" => "user", "content" => "x"}])
  end

  test "missing API key fails without calling the API" do
    Application.put_env(:patchwrit_api, :meta, req_options: [plug: {Req.Test, @stub}])
    Req.Test.stub(@stub, fn _conn -> flunk("Meta must not be called without a key") end)

    assert {:error, message} = Client.complete([%{"role" => "user", "content" => "ping"}])
    assert message =~ "MODEL_API_KEY"
  end

  test "non-2xx fails closed with the status" do
    Req.Test.stub(@stub, fn conn ->
      conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"error" => "unauthorized"})
    end)

    assert {:error, message} = Client.complete([%{"role" => "user", "content" => "ping"}])
    assert message =~ "401"
  end

  test "unexpected response shape is an error, not a silent pass" do
    Req.Test.stub(@stub, fn conn -> Req.Test.json(conn, %{"nope" => true}) end)

    assert {:error, message} = Client.complete([%{"role" => "user", "content" => "ping"}])
    assert message =~ "unexpected"
  end
end
