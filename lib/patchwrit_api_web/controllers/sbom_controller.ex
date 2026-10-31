defmodule PatchwritApiWeb.SbomController do
  @moduledoc """
  Downloads the CycloneDX SBOM for one analysis — exactly the
  resolved graph Patchwrit observed, nothing inferred.
  """

  use PatchwritApiWeb, :controller

  alias PatchwritApi.Analyses
  alias PatchwritApi.Analyses.Sbom

  def download(conn, %{"id" => id}) do
    analysis = Analyses.get_analysis!(id)
    filename = "patchwrit-sbom-#{String.slice(analysis.id, 0, 8)}.cdx.json"

    conn
    |> put_resp_content_type("application/vnd.cyclonedx+json")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> json(Sbom.cyclonedx(analysis))
  end
end
