defmodule PatchwritApi.GitHub do
  @moduledoc """
  Minimal GitHub REST client for public repository metadata.

  Currently used to populate the branch dropdown when a user tracks a
  repository. Dispatch still resolves the selected ref to a SHA with
  `git ls-remote`; branch metadata from GitHub is never trusted as the
  immutable analysis target.
  """

  alias PatchwritApi.Repositories.Repository

  @default_base_url "https://api.github.com"
  @max_branch_pages 10

  @type branch :: %{name: String.t(), sha: String.t() | nil}
  @type repository_branches :: %{
          default_branch: String.t() | nil,
          branches: [branch()]
        }

  @doc """
  Fetches a repository's default branch and all branches, following
  GitHub pagination up to a bounded number of pages.
  """
  @spec repository_branches(String.t()) :: {:ok, repository_branches()} | {:error, String.t()}
  def repository_branches(repository_url) do
    with {:ok, owner, repo} <- parse_repository_url(repository_url),
         {:ok, metadata} <- fetch_repository_metadata(owner, repo),
         {:ok, branches} <- fetch_branches(owner, repo) do
      {:ok,
       %{
         default_branch: metadata.default_branch,
         name: metadata.name,
         branches: branches
       }}
    end
  end

  # The repository's own metadata: its current full name (which follows
  # renames/redirects, unlike the typed URL) and default branch.
  defp fetch_repository_metadata(owner, repo) do
    case request_body("/repos/#{owner}/#{repo}") do
      {:ok, body} ->
        {:ok, %{default_branch: body["default_branch"], name: body["full_name"]}}

      {:error, message} ->
        {:error, message}
    end
  end

  defp fetch_branches(owner, repo) do
    fetch_branches_page("/repos/#{owner}/#{repo}/branches", [per_page: 100, page: 1], [], 1)
  end

  defp fetch_branches_page(_path, _params, _acc, page) when page > @max_branch_pages do
    {:error, "GitHub returned too many branch pages"}
  end

  defp fetch_branches_page(path, params, acc, page) do
    case request(path, params) do
      {:ok, body, headers} when is_list(body) ->
        branches =
          Enum.map(body, fn branch ->
            %{name: branch["name"], sha: get_in(branch, ["commit", "sha"])}
          end)

        case next_page_url(headers) do
          nil -> {:ok, acc ++ branches}
          next_url -> fetch_branches_page(next_url, [], acc ++ branches, page + 1)
        end

      {:ok, _body, _headers} ->
        {:error, "GitHub returned an unexpected branch response"}

      {:error, message} ->
        {:error, message}
    end
  end

  defp request(path, params \\ []) do
    config = Application.get_env(:patchwrit_api, :github, [])

    req =
      Req.new(
        base_url: Keyword.get(config, :base_url, @default_base_url),
        headers: [
          {"accept", "application/vnd.github+json"},
          {"x-github-api-version", "2022-11-28"},
          {"user-agent", "Patchwrit"}
        ]
      )
      |> maybe_put_token(Keyword.get(config, :token))
      |> Req.merge(Keyword.get(config, :req_options, []))

    case Req.get(req, url: path, params: params) do
      {:ok, %Req.Response{status: status, body: body, headers: headers}}
      when status in 200..299 ->
        {:ok, body, headers}

      {:ok, %Req.Response{status: 404}} ->
        {:error, "GitHub repository could not be found or is not public"}

      {:ok, %Req.Response{status: 403, body: body}} ->
        {:error,
         "GitHub API request was rejected: #{body["message"] || "rate limit or access denied"}"}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, "GitHub API returned #{status}: #{body["message"] || "unexpected response"}"}

      {:error, exception} ->
        {:error, "GitHub API request failed: #{Exception.message(exception)}"}
    end
  end

  # fetch_default_branch only needs the body, while branch fetching needs
  # pagination headers. Normalize those call sites here.
  defp request_body(path) do
    case request(path) do
      {:ok, body, _headers} -> {:ok, body}
      other -> other
    end
  end

  defp maybe_put_token(req, token) when is_binary(token) and token != "" do
    Req.merge(req, headers: [{"authorization", "Bearer #{token}"}])
  end

  defp maybe_put_token(req, _token), do: req

  defp next_page_url(headers) do
    headers
    |> Map.get("link", [])
    |> List.wrap()
    |> Enum.join(",")
    |> then(fn link ->
      case Regex.run(~r{<([^>]+)>;\s*rel="next"}, link) do
        [_, url] -> url
        _ -> nil
      end
    end)
  end

  defp parse_repository_url(repository_url) do
    case Regex.run(Repository.github_url_regex(), String.trim(to_string(repository_url))) do
      [_, owner, repo | _] -> {:ok, owner, repo}
      _ -> {:error, "repository URL must be a public GitHub repository URL"}
    end
  end
end
