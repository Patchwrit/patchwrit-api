defmodule PatchwritApi.Repo do
  use Ecto.Repo,
    otp_app: :patchwrit_api,
    adapter: Ecto.Adapters.Postgres
end
