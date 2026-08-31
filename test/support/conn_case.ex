defmodule StatifierExamplesWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use StatifierExamplesWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      # The default endpoint for testing
      @endpoint StatifierExamplesWeb.Endpoint

      use StatifierExamplesWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import StatifierExamplesWeb.ConnCase
    end
  end

  setup tags do
    :ok = checkout(tags)

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Checks this test out a sandboxed connection, shared with every other
  process unless the case is async.

  The sharing is the part that matters here rather than the checkout: a
  LiveView test drives a *separate* process, and this app's Run button now
  starts a durable run that writes to the database from inside it. Without
  the shared owner that write finds no connection and the page fails in a
  way that says nothing about the page.
  """
  @spec checkout(map()) :: :ok
  def checkout(tags) do
    pid =
      Sandbox.start_owner!(StatifierExamples.Repo, shared: not tags[:async])

    on_exit(fn -> Sandbox.stop_owner(pid) end)

    :ok
  end
end
