defmodule UpgradeHost.Repo do
  @moduledoc "The host's Ecto repo, on Postgres."

  use Ecto.Repo, otp_app: :upgrade_host, adapter: Ecto.Adapters.Postgres
end
