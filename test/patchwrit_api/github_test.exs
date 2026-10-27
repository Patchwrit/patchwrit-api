defmodule PatchwritApi.GitHubTest do
  use ExUnit.Case, async: false

  alias PatchwritApi.GitHub

  @stub PatchwritApi.GitHubStub
  @url "https://github.com/spring-petclinic/spring-framework-petclinic"

  setup do
    Req.Test.set_req_test_to_shared()

    previous = Application.get_env(:patchwrit_api, :github)

    Application.put_env(:patchwrit_api, :github,
      base_url: "https://api.github.com",
      req_options: [plug: {Req.Test, @stub}]
    )

    on_exit(fn ->
      if previous,
        do: Application.put_env(:patchwrit_api, :github, previous),
        else: Application.delete_env(:patchwrit_api, :github)
    end)

    :ok
  end

  test "repository_branches returns the default branch and follows pagination" do
    Req.Test.stub(@stub, fn conn ->
      case {conn.request_path, conn.query_string} do
        {"/repos/spring-petclinic/spring-framework-petclinic", _} ->
          Req.Test.json(conn, %{"default_branch" => "main"})

        {"/repos/spring-petclinic/spring-framework-petclinic/branches", query} ->
          params = URI.decode_query(query)

          if params["page"] == "2" do
            Req.Test.json(conn, [
              %{"name" => "javaconfig", "commit" => %{"sha" => "bbb"}}
            ])
          else
            conn
            |> Plug.Conn.put_resp_header(
              "link",
              "<https://api.github.com/repos/spring-petclinic/spring-framework-petclinic/branches?per_page=100&page=2>; rel=\"next\""
            )
            |> Req.Test.json([
              %{"name" => "main", "commit" => %{"sha" => "aaa"}},
              %{"name" => "5.3.x", "commit" => %{"sha" => "ccc"}}
            ])
          end
      end
    end)

    assert {:ok, result} = GitHub.repository_branches(@url)
    assert result.default_branch == "main"
    assert Enum.map(result.branches, & &1.name) == ["main", "5.3.x", "javaconfig"]
    assert Enum.map(result.branches, & &1.sha) == ["aaa", "ccc", "bbb"]
  end

  test "repository_branches rejects non-GitHub URLs without calling GitHub" do
    Req.Test.stub(@stub, fn _conn -> flunk("GitHub must not be called") end)

    assert {:error, message} = GitHub.repository_branches("https://example.com/a/b")
    assert message =~ "public GitHub repository URL"
  end

  test "repository_branches maps a missing repository to a useful error" do
    Req.Test.stub(@stub, fn conn ->
      conn
      |> Plug.Conn.put_status(404)
      |> Req.Test.json(%{"message" => "Not Found"})
    end)

    assert {:error, message} = GitHub.repository_branches(@url)
    assert message =~ "could not be found"
  end
end
