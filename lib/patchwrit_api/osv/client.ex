defmodule PatchwritApi.Osv.Client do
  @moduledoc """
  Minimal client for the public OSV API (https://api.osv.dev).

  No credentials. Two steps: `POST /v1/querybatch` with every resolved
  dependency (returns vulnerability ids only), then `GET /v1/vulns/:id`
  for the details of each actual hit. Configuration comes from
  `config :patchwrit_api, :osv` (`base_url`, `req_options` — Req.Test in
  tests).

  The scan fails closed: any OSV error returns `{:error, message}` and
  no findings are recorded, so `osv_scanned_at` is never set on a
  partial scan.
  """

  @default_base_url "https://api.osv.dev"
  @batch_size 500

  @doc """
  Scans dependency maps from the worker result and returns finding
  attribute maps (without `analysis_id`), one per (vulnerability,
  package) pair.
  """
  @spec scan_dependencies([map()]) :: {:ok, [map()]} | {:error, String.t()}
  def scan_dependencies(dependencies) when is_list(dependencies) do
    packages = Enum.uniq_by(dependencies, &package_key/1)

    with {:ok, hits} <- query_batch(packages),
         {:ok, vulns} <- fetch_vulnerabilities(hits) do
      {:ok, build_findings(hits, vulns)}
    end
  end

  # -- querybatch -----------------------------------------------------------

  defp query_batch(packages) do
    packages
    |> Enum.chunk_every(@batch_size)
    |> Enum.reduce_while({:ok, []}, fn chunk, {:ok, acc} ->
      queries =
        Enum.map(chunk, fn dep ->
          %{
            "package" => %{"name" => package_name(dep), "ecosystem" => "Maven"},
            "version" => dep["version"]
          }
        end)

      case request(:post, "/v1/querybatch", json: %{"queries" => queries}) do
        {:ok, %{"results" => results}} when length(results) == length(chunk) ->
          hits =
            chunk
            |> Enum.zip(results)
            |> Enum.flat_map(fn {dep, result} ->
              Enum.map(result["vulns"] || [], &{dep, &1["id"]})
            end)

          {:cont, {:ok, acc ++ hits}}

        {:ok, _body} ->
          {:halt, {:error, "OSV returned an unexpected querybatch response"}}

        {:error, message} ->
          {:halt, {:error, message}}
      end
    end)
  end

  # -- vulnerability details -------------------------------------------------

  defp fetch_vulnerabilities(hits) do
    hits
    |> Enum.map(&elem(&1, 1))
    |> Enum.uniq()
    |> Enum.reduce_while({:ok, %{}}, fn id, {:ok, acc} ->
      case request(:get, "/v1/vulns/#{id}") do
        {:ok, %{"id" => ^id} = vuln} -> {:cont, {:ok, Map.put(acc, id, vuln)}}
        {:ok, _body} -> {:halt, {:error, "OSV returned an unexpected vulnerability response"}}
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
  end

  # -- finding construction ----------------------------------------------------

  defp build_findings(hits, vulns) do
    Enum.map(hits, fn {dep, osv_id} ->
      vuln = Map.fetch!(vulns, osv_id)
      name = package_name(dep)

      %{
        "osv_id" => osv_id,
        "package_name" => name,
        "package_version" => dep["version"],
        "summary" => vuln["summary"],
        "severity" => severity(vuln),
        "fixed_versions" => fixed_versions(vuln, name),
        "aliases" => vuln["aliases"] || [],
        "raw" => vuln
      }
    end)
  end

  # Prefer the CVSS vector string; GHSA entries without one carry a
  # coarse severity in database_specific (e.g. "HIGH").
  defp severity(vuln) do
    case vuln["severity"] do
      [%{"score" => score} | _] -> score
      _ -> get_in(vuln, ["database_specific", "severity"])
    end
  end

  defp fixed_versions(vuln, package_name) do
    (vuln["affected"] || [])
    |> Enum.filter(fn affected ->
      get_in(affected, ["package", "name"]) == package_name and
        get_in(affected, ["package", "ecosystem"]) == "Maven"
    end)
    |> Enum.flat_map(fn affected ->
      Enum.flat_map(affected["ranges"] || [], fn range ->
        Enum.flat_map(range["events"] || [], fn
          %{"fixed" => fixed} -> [fixed]
          _event -> []
        end)
      end)
    end)
    |> Enum.uniq()
  end

  # -- HTTP -----------------------------------------------------------------

  defp request(method, path, opts \\ []) do
    config = Application.get_env(:patchwrit_api, :osv, [])

    req =
      Req.new(
        base_url: Keyword.get(config, :base_url, @default_base_url),
        headers: [{"user-agent", "Patchwrit"}]
      )
      |> Req.merge(Keyword.get(config, :req_options, []))

    result =
      case method do
        :get -> Req.get(req, [url: path] ++ opts)
        :post -> Req.post(req, [url: path] ++ opts)
      end

    case result do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status}} ->
        {:error, "OSV API returned #{status}"}

      {:error, exception} ->
        {:error, "OSV API request failed: #{Exception.message(exception)}"}
    end
  end

  defp package_name(dep), do: "#{dep["group_id"]}:#{dep["artifact_id"]}"
  defp package_key(dep), do: {package_name(dep), dep["version"]}
end
