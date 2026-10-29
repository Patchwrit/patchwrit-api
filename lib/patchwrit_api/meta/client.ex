defmodule PatchwritApi.Meta.Client do
  @moduledoc """
  Minimal client for the Meta Model API (https://api.meta.ai/v1).

  Phoenix-side only: the API key comes from the `MODEL_API_KEY`
  environment variable via runtime config and is never sent to a
  worker. Tribunal roles call this through Phoenix so every model
  request can be validated, persisted, and cost-audited centrally.

  Configuration comes from `config :patchwrit_api, :meta`:

      [
        api_key: "…",          # MODEL_API_KEY, never committed
        base_url: "https://api.meta.ai/v1",
        advocate_model: "muse-spark-1.3",
        judge_model: "muse-wonder-1.0",
        req_options: []        # test injection point (Req.Test)
      ]
  """

  @default_base_url "https://api.meta.ai/v1"
  @default_advocate_model "muse-spark-1.3"
  @default_judge_model "muse-wonder-1.0"

  @type completion :: %{
          content: String.t(),
          model: String.t(),
          usage: map()
        }

  @doc "Model used for Prosecutor/Defender calls."
  def advocate_model do
    Keyword.get(config(), :advocate_model, @default_advocate_model)
  end

  @doc "Model used for Judge calls."
  def judge_model do
    Keyword.get(config(), :judge_model, @default_judge_model)
  end

  @doc """
  Runs one chat completion. `messages` is a list of
  `%{"role" => ..., "content" => ...}` maps (atom keys accepted).
  Options: `:model` (default `advocate_model/0`), `:temperature`.
  """
  @spec complete([map()], keyword()) :: {:ok, completion()} | {:error, String.t()}
  def complete(messages, opts \\ []) when is_list(messages) do
    with {:ok, api_key} <- configured_key() do
      model = Keyword.get(opts, :model, advocate_model())

      payload =
        %{
          "model" => model,
          "messages" => Enum.map(messages, &normalize_message/1)
        }
        |> maybe_put("temperature", Keyword.get(opts, :temperature))

      case request(api_key, payload) do
        {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]} = body}
        when is_binary(content) ->
          {:ok, %{content: content, model: body["model"] || model, usage: body["usage"] || %{}}}

        {:ok, _body} ->
          {:error, "Meta model API returned an unexpected response"}

        {:error, message} ->
          {:error, message}
      end
    end
  end

  # -- HTTP -----------------------------------------------------------------

  defp request(api_key, payload) do
    req =
      Req.new(
        base_url: Keyword.get(config(), :base_url, @default_base_url),
        # Reasoning models regularly exceed Req's 15s default.
        receive_timeout: Keyword.get(config(), :receive_timeout_ms, 120_000),
        headers: [
          {"authorization", "Bearer #{api_key}"},
          {"user-agent", "Patchwrit"}
        ]
      )
      |> Req.merge(Keyword.get(config(), :req_options, []))

    case Req.post(req, url: "/chat/completions", json: payload) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status}} ->
        {:error, "Meta model API returned #{status}"}

      {:error, exception} ->
        {:error, "Meta model API request failed: #{Exception.message(exception)}"}
    end
  end

  # -- config ---------------------------------------------------------------

  defp configured_key do
    case Keyword.get(config(), :api_key) do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ -> {:error, "Meta model API key is not configured (set MODEL_API_KEY)"}
    end
  end

  defp config, do: Application.get_env(:patchwrit_api, :meta, [])

  defp normalize_message(%{} = message) do
    %{
      "role" => to_string(message["role"] || message[:role] || "user"),
      "content" => to_string(message["content"] || message[:content] || "")
    }
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
