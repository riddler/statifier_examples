defmodule StatifierExamplesWeb.JourneyHostScopeTest do
  @moduledoc """
  The scope `StatifierExamplesWeb.JourneyHost` answers beside a Journey:
  the one the execution records, and the refusal for an execution whose
  recorded scope does not fit the Path the name gives.
  """

  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Riddler.Journey.Scope
  alias StatifierExamples.Charts.Durable
  alias StatifierExamples.Library.Onboarding
  alias StatifierExamples.Repo
  alias StatifierExamples.Signup.Journey
  alias StatifierExamplesWeb.JourneyHost

  setup do
    :ok = Sandbox.checkout(Repo)
    :ok
  end

  defp riverside do
    {:ok, scope} = Scope.new("branch", "riverside")
    scope
  end

  defp onboarding(opts) do
    id = "host-scope-#{System.unique_integer([:positive])}"
    {:ok, ^id} = Journey.start(id, Onboarding.options() ++ opts)
    id
  end

  # Sabotage (run): made `JourneyHost.start/2` start the Journey without
  # its `scope:` option. The execution recorded no scope and this went red
  # on the first match.
  test "start records the scope it was given, and present answers it" do
    assert {:ok, journey, _answer} = JourneyHost.start(Onboarding.key(), riverside())
    assert {:ok, "branch_onboarding", execution_id} = JourneyHost.parse(journey)

    assert {:ok, %{"kind" => "branch", "id" => "riverside"}} = Durable.scope(execution_id)
    assert {:ok, scope, _answer} = JourneyHost.present(journey)
    assert scope == riverside()
  end

  # Sabotage (run): made `recorded_scope/2` answer the riverside branch
  # scope for a library Path execution that records none. The unscoped
  # onboarding answered that scope and this went red on the first match.
  test "a library Path execution that records no scope is a Journey the host does not have" do
    journey = JourneyHost.journey(Onboarding.key(), onboarding([]))

    assert {:error, :no_such_journey} = JourneyHost.scope_of(journey)
    assert {:error, :no_such_journey} = JourneyHost.present(journey)
  end

  # Sabotage (run): made `recorded_scope/2` answer the open scope for the
  # signup Path whatever the execution records. The branch's onboarding,
  # named without its page key, answered the open scope and this went red.
  test "an execution under a branch scope is not opened as the signup Path's" do
    execution_id = onboarding(scope: riverside())

    assert {:ok, scope} =
             JourneyHost.scope_of(JourneyHost.journey(Onboarding.key(), execution_id))

    assert scope == riverside()

    assert {:error, :no_such_journey} =
             JourneyHost.scope_of(JourneyHost.journey(nil, execution_id))
  end
end
