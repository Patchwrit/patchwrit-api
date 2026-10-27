defmodule PatchwritApi.Repositories.Repository do
  @moduledoc """
  A user-tracked public GitHub Maven repository.

  The repository record holds editable defaults. Each Analysis snapshots
  the URL, ref, and JDK version when a run starts, so editing this record
  never rewrites the meaning of historical analyses.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @java_versions ~w(17 21)
  @github_url_regex ~r{\Ahttps://github\.com/([\w.-]+)/([\w.-]+?)(\.git)?/?\z}

  schema "repositories" do
    field :repository_url, :string
    field :default_ref, :string, default: "HEAD"
    field :java_version, :string, default: "17"

    has_many :analyses, PatchwritApi.Analyses.Analysis

    timestamps(type: :utc_datetime)
  end

  def java_versions, do: @java_versions
  def github_url_regex, do: @github_url_regex

  def changeset(repository, attrs) do
    repository
    |> cast(attrs, [:repository_url, :default_ref, :java_version])
    |> normalize_repository_url()
    |> validate_required([:repository_url, :default_ref, :java_version])
    |> validate_format(:repository_url, @github_url_regex,
      message: "must be a public GitHub repository URL"
    )
    |> validate_inclusion(:java_version, @java_versions)
    |> unique_constraint(:repository_url)
  end

  @doc "Returns the canonical `https://github.com/owner/repo` form, or nil."
  def canonical_url(url) when is_binary(url) do
    case Regex.run(@github_url_regex, String.trim(url)) do
      [_, owner, repo | _] -> "https://github.com/#{owner}/#{repo}"
      _ -> nil
    end
  end

  def canonical_url(_url), do: nil

  defp normalize_repository_url(changeset) do
    update_change(changeset, :repository_url, fn url ->
      canonical_url(url) || (is_binary(url) && String.trim(url)) || url
    end)
  end
end
