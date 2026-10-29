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

  test "sends a chat completion with bearer auth and returns content + usage" do
    parent = self()

    Req.Test.stub(@stub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(parent, {:meta_request, conn, Jason.decode!(body)})

      Req.Test.json(conn, %{
        "model" => "muse-spark-1.3",
        "choices" => [
          %{"message" => %{"role" => "assistant", "content" => "pong"}}
        ],
        "usage" => %{"prompt_tokens" => 5, "completion_tokens" => 1, "total_tokens" => 6}
      })
    end)

    assert {:ok, result} =
             Client.complete([%{"role" => "user", "content" => "ping"}])

    assert result.content == "pong"
    assert result.model == "muse-spark-1.3"
    assert result.usage["total_tokens"] == 6

    assert_received {:meta_request, conn, payload}
    assert conn.request_path == "/v1/chat/completions"
    assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer test-key"]
    assert payload["model"] == "muse-spark-1.3"
    assert payload["messages"] == [%{"role" => "user", "content" => "ping"}]
  end

  test "explicit model option wins (judge model)" do
    Req.Test.stub(@stub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert Jason.decode!(body)["model"] == "muse-wonder-1.0"

      Req.Test.json(conn, %{
        "choices" => [%{"message" => %{"content" => "judged"}}]
      })
    end)

    assert {:ok, %{content: "judged"}} =
             Client.complete([%{role: "user", content: "case"}], model: Client.judge_model())
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
