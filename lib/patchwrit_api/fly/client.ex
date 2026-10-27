defmodule PatchwritApi.Fly.Client do
  @moduledoc """
  Minimal client for the Fly Machines API.

  This module owns every HTTP call to Fly. Callers get normalized
  `{:ok, result}` / `{:error, error}` tuples and never see the API
  token, raw headers, or transport details.

  Configuration comes from `config :patchwrit_api, :fly`:

      [
        api_token: "…",                 # FLY_API_TOKEN, never committed
        app_name: "patchwrit-machines", # FLY_APP_NAME
        base_url: "https://api.machines.dev",
        req_options: []                 # test injection point (Req.Test)
      ]
  """

  @default_base_url "https://api.machines.dev"
  @default_region "iad"

  # Allowlist keys -> full image references. Raw image strings from
  # callers are rejected; extend this map deliberately, in a PR.
  @images %{
    "busybox" => "registry-1.docker.io/library/busybox:latest",
    "alpine" => "registry-1.docker.io/library/alpine:latest"
  }

  @type result :: %{status: non_neg_integer(), data: term(), duration_ms: non_neg_integer()}
  @type error :: %{status: non_neg_integer(), message: String.t(), duration_ms: non_neg_integer()}

  @doc "Creates a small test Machine from allowlisted inputs."
  @spec create_machine(map()) :: {:ok, result()} | {:error, error()}
  def create_machine(attrs \\ %{})

  def create_machine(attrs) when is_map(attrs) do
    with {:ok, payload} <- build_create_payload(attrs),
         {:ok, config} <- configured() do
      request(config, :post, machines_path(config), json: payload, kind: :machine)
    end
  end

  def create_machine(_attrs), do: invalid("machine attributes must be a map")

  @doc """
  Creates a Machine running the configured worker image.

  The image comes only from server config (`WORKER_IMAGE`) and must be
  pinned by digest. `env` is passed into the Machine; it carries the
  PATCHWRIT_* job variables including the scoped callback token.
  """
  @spec create_worker_machine(map()) :: {:ok, result()} | {:error, error()}
  def create_worker_machine(attrs) when is_map(attrs) do
    image_key = attrs |> fetch_attr("image_key", "smoke") |> to_string()

    with {:ok, config} <- configured(),
         {:ok, image} <- worker_image(config, image_key),
         {:ok, name} <- validate_name(fetch_attr(attrs, "name", nil)) do
      env =
        Map.new(fetch_attr(attrs, "env", %{}), fn {k, v} -> {to_string(k), to_string(v)} end)

      payload =
        %{
          "region" => fetch_attr(attrs, "region", @default_region),
          "config" => %{
            "image" => image,
            "env" => env,
            "guest" => %{
              "cpu_kind" => "shared",
              "cpus" => 1,
              "memory_mb" => if(image_key in ["jdk17", "jdk21"], do: 1024, else: 256)
            }
          }
        }
        |> maybe_put_name(name)

      request(config, :post, machines_path(config), json: payload, kind: :machine)
    end
  end

  def create_worker_machine(_attrs), do: invalid("worker machine attributes must be a map")

  @doc "Returns the configured digest-pinned image reference for an image key."
  @spec selected_worker_image(String.t()) :: {:ok, String.t()} | {:error, error()}
  def selected_worker_image(image_key \\ "smoke") do
    with {:ok, config} <- configured() do
      worker_image(config, to_string(image_key))
    end
  end

  defp worker_image(config, image_key) do
    image =
      Map.get(config.worker_images, image_key) ||
        if image_key == "smoke", do: Map.get(config, :worker_image)

    if is_binary(image) and String.contains?(image, "@sha256:") do
      {:ok, image}
    else
      {:error,
       %{
         status: 503,
         message:
           "worker image for #{image_key} is not configured with a pinned digest (set WORKER_IMAGE_#{String.upcase(image_key)})",
         duration_ms: 0
       }}
    end
  end

  @doc "Lists Machines in the configured app."
  @spec list_machines() :: {:ok, result()} | {:error, error()}
  def list_machines do
    with {:ok, config} <- configured() do
      request(config, :get, machines_path(config), kind: :machines)
    end
  end

  @doc "Fetches one Machine by id."
  @spec get_machine(String.t()) :: {:ok, result()} | {:error, error()}
  def get_machine(id) do
    with {:ok, id} <- validate_id(id),
         {:ok, config} <- configured() do
      request(config, :get, machine_path(config, id), kind: :machine)
    end
  end

  @doc "Starts a stopped Machine."
  @spec start_machine(String.t()) :: {:ok, result()} | {:error, error()}
  def start_machine(id), do: machine_action(id, "start")

  @doc "Stops a running Machine."
  @spec stop_machine(String.t()) :: {:ok, result()} | {:error, error()}
  def stop_machine(id), do: machine_action(id, "stop")

  @doc "Destroys a Machine. Uses force so running Machines can be removed."
  @spec delete_machine(String.t()) :: {:ok, result()} | {:error, error()}
  def delete_machine(id) do
    with {:ok, id} <- validate_id(id),
         {:ok, config} <- configured() do
      request(config, :delete, machine_path(config, id), params: [force: true], kind: :delete)
    end
  end

  ## Create payload: validation happens before any HTTP call.

  defp build_create_payload(attrs) do
    image_key = attrs |> fetch_attr("image", "busybox") |> to_string()
    region = attrs |> fetch_attr("region", @default_region) |> to_string()
    name = fetch_attr(attrs, "name", nil)

    with {:ok, image} <- fetch_image(image_key),
         {:ok, region} <- validate_region(region),
         {:ok, name} <- validate_name(name) do
      payload =
        %{
          "region" => region,
          "config" => %{
            "image" => image,
            "auto_destroy" => false,
            "init" => %{"cmd" => ["/bin/sh", "-c", "sleep 86400"]},
            "guest" => %{"cpu_kind" => "shared", "cpus" => 1, "memory_mb" => 256}
          }
        }
        |> maybe_put_name(name)

      {:ok, payload}
    end
  end

  defp fetch_attr(attrs, key, default) do
    Map.get(attrs, key) || Map.get(attrs, String.to_existing_atom(key), default) || default
  rescue
    ArgumentError -> Map.get(attrs, key, default)
  end

  defp fetch_image(key) do
    case Map.fetch(@images, key) do
      {:ok, image} -> {:ok, image}
      :error -> invalid("image must be one of: #{@images |> Map.keys() |> Enum.join(", ")}")
    end
  end

  defp validate_region(region) do
    if Regex.match?(~r/^[a-z]{3}$/, region),
      do: {:ok, region},
      else: invalid("region must be a three-letter Fly region code")
  end

  defp validate_name(nil), do: {:ok, nil}

  defp validate_name(name) when is_binary(name) do
    if Regex.match?(~r/^[a-z0-9][a-z0-9-]{0,62}$/, name),
      do: {:ok, name},
      else: invalid("name must be lowercase letters, digits, and dashes")
  end

  defp validate_name(_name), do: invalid("name must be a string")

  defp maybe_put_name(payload, nil), do: payload
  defp maybe_put_name(payload, name), do: Map.put(payload, "name", name)

  defp validate_id(id) when is_binary(id) do
    if Regex.match?(~r/^[A-Za-z0-9_-]+$/, id),
      do: {:ok, id},
      else: invalid("machine id is invalid")
  end

  defp validate_id(_id), do: invalid("machine id is invalid")

  ## HTTP plumbing

  defp machine_action(id, action) do
    with {:ok, id} <- validate_id(id),
         {:ok, config} <- configured() do
      request(config, :post, "#{machine_path(config, id)}/#{action}", json: %{}, kind: :machine)
    end
  end

  defp machines_path(config), do: "/v1/apps/#{config.app_name}/machines"
  defp machine_path(config, id), do: "#{machines_path(config)}/#{id}"

  defp configured do
    fly = Application.get_env(:patchwrit_api, :fly, [])
    token = Keyword.get(fly, :api_token)
    app = Keyword.get(fly, :app_name)

    if is_binary(token) and token != "" and is_binary(app) and app != "" do
      {:ok,
       %{
         api_token: token,
         app_name: app,
         base_url: Keyword.get(fly, :base_url, @default_base_url),
         worker_image: Keyword.get(fly, :worker_image),
         worker_images: normalize_worker_images(Keyword.get(fly, :worker_images, [])),
         req_options: Keyword.get(fly, :req_options, [])
       }}
    else
      {:error,
       %{
         status: 503,
         message: "Fly is not configured (set FLY_API_TOKEN and FLY_APP_NAME)",
         duration_ms: 0
       }}
    end
  end

  defp normalize_worker_images(images) when is_map(images) do
    Map.new(images, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_worker_images(images) when is_list(images) do
    Map.new(images, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_worker_images(_images), do: %{}

  defp request(config, method, path, opts) do
    {kind, req_opts} = Keyword.pop!(opts, :kind)
    started = System.monotonic_time(:millisecond)

    req =
      Req.new(
        base_url: config.base_url,
        headers: [
          {"authorization", "Bearer #{config.api_token}"},
          {"content-type", "application/json"}
        ]
      )
      |> Req.merge(config.req_options)

    result =
      case apply(Req, method, [req, [url: path] ++ req_opts]) do
        {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
          {:ok, %{status: status, data: normalize(body, kind), duration_ms: elapsed(started)}}

        {:ok, %Req.Response{status: status, body: body}} ->
          {:error, %{status: status, message: error_message(body), duration_ms: elapsed(started)}}

        {:error, exception} ->
          {:error,
           %{
             status: 502,
             message: "Fly request failed: #{Exception.message(exception)}",
             duration_ms: elapsed(started)
           }}
      end

    result
  end

  defp elapsed(started), do: System.monotonic_time(:millisecond) - started

  # Keep only stable Machine fields; never pass raw upstream payloads through.
  defp normalize(body, :machine) when is_map(body) do
    %{
      id: body["id"],
      name: body["name"],
      state: body["state"],
      region: body["region"],
      instance_id: body["instance_id"]
    }
  end

  defp normalize(body, :machines) when is_list(body), do: Enum.map(body, &normalize(&1, :machine))
  defp normalize(%{"id" => id, "deleted" => deleted}, :delete), do: %{id: id, deleted: deleted}
  defp normalize(_body, :delete), do: %{deleted: true}
  defp normalize(body, _kind), do: body

  defp error_message(%{"error" => message}) when is_binary(message), do: message
  defp error_message(%{"message" => message}) when is_binary(message), do: message
  defp error_message(_body), do: "Fly request failed"

  defp invalid(message), do: {:error, %{status: 422, message: message, duration_ms: 0}}
end
