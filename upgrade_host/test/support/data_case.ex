defmodule UpgradeHost.DataCase do
  @moduledoc """
  A test case on the sandboxed repo. Not async: an Oban drain and a
  bounded invoke attempt run work outside the test process, so the
  connection is shared for the length of each test.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      import Ecto.Query
      import UpgradeHost.DataCase

      alias UpgradeHost.Repo
    end
  end

  setup do
    pid = Sandbox.start_owner!(UpgradeHost.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(pid) end)
    :ok
  end
end
