defmodule PatchwritApi.Meta.Client do
  @moduledoc """
  Minimal client for the Meta Model API (https://api.meta.ai/v1).

  Phoenix-side only: the API key comes from the `MODEL_API_KEY`
  environment variable via runtime config and is never sent to a
  worker. Tribunal roles call this through Phoenix so every model
  request can be validated, persisted, and cost-audited centrally.

  Calls use the Responses endpoint (`/responses`), not Chat
  Completions: Meta's prompt-prefix cache only engages there. Cached
  tokens are observable in the normalized usage map
  (`prompt_tokens_details.cached_tokens`); on Chat Completions they
  were always reported as 0.

  Configuration comes from `config :patchwrit_api, :meta`:

      [
        api_key: "…",          # MODEL_API_KEY, never committed
        base_url: "https://api.meta.ai/v1",
        advocate_model: "muse-spark-1.3",
        judge_model: "muse-wonder-1.0",
        prompt_cache_retention: "in_memory",  # or "24h" (a hint)
        req_options: []        # test injection point (Req.Test)
      ]
  """

  @default_base_url "https://api.meta.ai/v1"
  @default_advocate_model "muse-spark-1.3"
  @default_judge_model "muse-wonder-1.0"
  @default_cache_retention "in_memory"

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
  Runs one completion. `messages` is a list of
  `%{"role" => ..., "content" => ...}` maps (atom keys accepted):
  `system` messages become the Responses `instructions`, the rest the
  `input`, preserving order so a shared leading block (instructions +
  first input) forms a cacheable prefix.

  Options: `:model` (default `advocate_model/0`), `:temperature`,
  `:prompt_cache_key` (routes same-prefix requests to the same cache),
  `:prompt_cache_retention` (`"in_memory"` or `"24h"`, default from
  config). Usage is normalized to the token shape the tribunal
  persists: `prompt_tokens` / `completion_tokens` / `total_tokens`,
  with `prompt_tokens_details.cached_tokens` and
  `completion_tokens_details.reasoning_tokens` when reported.
  """
  @spec complete([map()], keyword()) :: {:ok, completion()} | {:error, String.t()}
  def complete(messages, opts \\ []) when is_list(messages) do
    with {:ok, api_key} <- configured_key() do
      model = Keyword.get(opts, :model, advocate_model())
      {instructions, input} = split_messages(messages)

      payload =
        %{"model" => model, "input" => input}
        |> maybe_put("instructions", instructions)
        |> maybe_put("temperature", Keyword.get(opts, :temperature))
        |> maybe_put("prompt_cache_key", Keyword.get(opts, :prompt_cache_key))
        |> Map.put(
          "prompt_cache_retention",
          Keyword.get(opts, :prompt_cache_retention) ||
            Keyword.get(config(), :prompt_cache_retention, @default_cache_retention)
        )

      case request(api_key, payload) do
        {:ok, body} ->
          case response_text(body) do
            content when is_binary(content) and content != "" ->
              {:ok,
               %{
                 content: content,
                 model: body["model"] || model,
                 usage: normalize_usage(body["usage"] || %{})
               }}

            _ ->
              {:error, "Meta model API returned an unexpected response"}
          end

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

    case Req.post(req, url: "/responses", json: payload) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status}} ->
        {:error, "Meta model API returned #{status}"}

      {:error, exception} ->
        {:error, "Meta model API request failed: #{Exception.message(exception)}"}
    end
  end

  # -- responses shape --------------------------------------------------------

  defp split_messages(messages) do
    normalized = Enum.map(messages, &normalize_message/1)
    {system, rest} = Enum.split_with(normalized, &(&1["role"] == "system"))

    instructions =
      case Enum.map(system, & &1["content"]) do
        [] -> nil
        contents -> Enum.join(contents, "\n\n")
      end

    {instructions, rest}
  end

  # The assistant text of a Responses result: the message item's
  # output_text parts (reasoning items carry no text for us). The
  # `output_text` convenience field is accepted as a fallback.
  defp response_text(body) do
    from_output(body["output"]) || body_output_text(body)
  end

  defp from_output(output) when is_list(output) do
    Enum.find_value(output, fn
      %{"type" => "message", "content" => content} when is_list(content) ->
        texts =
          for %{"type" => "output_text", "text" => text} <- content,
              is_binary(text),
              do: text

        case texts do
          [] -> nil
          _ -> Enum.join(texts, "")
        end

      _ ->
        nil
    end)
  end

  defp from_output(_), do: nil

  defp body_output_text(%{"output_text" => text}) when is_binary(text), do: text
  defp body_output_text(_body), do: nil

  defp normalize_usage(usage) do
    %{}
    |> maybe_put("prompt_tokens", usage["input_tokens"])
    |> maybe_put("completion_tokens", usage["output_tokens"])
    |> maybe_put(
      "total_tokens",
      usage["total_tokens"] ||
        sum_present(usage["input_tokens"], usage["output_tokens"])
    )
    |> maybe_put(
      "prompt_tokens_details",
      details(usage["input_tokens_details"], "cached_tokens")
    )
    |> maybe_put(
      "completion_tokens_details",
      details(usage["output_tokens_details"], "reasoning_tokens")
    )
  end

  defp sum_present(a, b) when is_integer(a) and is_integer(b), do: a + b
  defp sum_present(_, _), do: nil

  defp details(%{} = source, key) do
    case source[key] do
      value when is_integer(value) -> %{key => value}
      _ -> nil
    end
  end

  defp details(_, _), do: nil

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
