defmodule PatchwritApi.Git do
  @moduledoc "Small git helpers. Pinning a ref to a SHA uses ls-remote: no clone, no execution of repo code."

  @spec resolve_sha(String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def resolve_sha(repository_url, ref) do
    ref = if ref in [nil, ""], do: "HEAD", else: ref

    case System.cmd("git", ["ls-remote", repository_url, ref], stderr_to_stdout: true) do
      {output, 0} ->
        case String.split(output) do
          [sha | _] -> {:ok, sha}
          [] -> {:error, "ref #{ref} not found in #{repository_url}"}
        end

      {output, _code} ->
        {:error, "git ls-remote failed: #{String.trim(output)}"}
    end
  rescue
    e -> {:error, "git ls-remote failed: #{Exception.message(e)}"}
  end
end
