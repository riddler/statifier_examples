defmodule StatifierExamplesWeb.JourneyAccessTest do
  @moduledoc """
  `StatifierExamplesWeb.JourneyAccess` asked as `Riddler.Journey.Access`
  asks it: who holds which scope, and which scope a Journey an actor
  starts runs under.
  """

  use ExUnit.Case, async: true

  alias Riddler.Journey.{Access, Scope}
  alias StatifierExamplesWeb.JourneyAccess

  doctest JourneyAccess

  @visitor %{visitor: "P-1001", librarian_of: nil}
  @librarian %{visitor: "P-1001", librarian_of: "riverside"}

  defp scope(kind, id) do
    {:ok, scope} = Scope.new(kind, id)
    scope
  end

  test "a visitor holds the open scope and its own patron scope, and a librarian its branch" do
    assert JourneyAccess.scopes(@visitor) == [
             JourneyAccess.open_scope(),
             scope("patron", "P-1001")
           ]

    assert JourneyAccess.scopes(@librarian) == [
             JourneyAccess.open_scope(),
             scope("patron", "P-1001"),
             scope("branch", "riverside")
           ]
  end

  # member?/2 and scopes/1 agree, as the behaviour asks of a host.
  #
  # Sabotage (run): made `member?/2` answer `true` for every branch scope.
  # The other branch was admitted and this went red.
  test "member? is true for exactly the scopes an actor holds" do
    for actor <- [@visitor, @librarian, nil, "anyone"],
        scope <- [
          JourneyAccess.open_scope(),
          scope("patron", "P-1001"),
          scope("patron", "P-2002"),
          scope("branch", "riverside"),
          scope("branch", "hillside")
        ] do
      assert JourneyAccess.member?(actor, scope) == scope in JourneyAccess.scopes(actor)
    end

    assert :ok = Access.check(JourneyAccess, @librarian, scope("branch", "riverside"), :submit)

    assert {:error, :no_such_journey} =
             Access.check(JourneyAccess, @librarian, scope("branch", "hillside"), :present)

    assert {:error, :no_such_journey} =
             Access.check(JourneyAccess, @visitor, scope("branch", "riverside"), :back)

    assert {:error, :no_such_journey} =
             Access.check(JourneyAccess, @visitor, scope("patron", "P-2002"), :present)
  end

  test "a Journey starts under the actor's own scope of the Path's kind" do
    assert {:ok, scope("branch", "riverside")} == JourneyAccess.start_scope("branch", @librarian)
    assert :error == JourneyAccess.start_scope("branch", @visitor)
    assert {:ok, scope("patron", "P-1001")} == JourneyAccess.start_scope("patron", @visitor)
    assert :error == JourneyAccess.start_scope("patron", %{visitor: nil, librarian_of: nil})
    assert {:ok, JourneyAccess.open_scope()} == JourneyAccess.start_scope("open", nil)
    assert :error == JourneyAccess.start_scope("parcel", @librarian)
  end

  test "the actor is read from the session's two keys, and an empty one is none" do
    assert JourneyAccess.actor(%{"visitor" => "P-1001", "librarian_of" => "riverside"}) ==
             @librarian

    assert JourneyAccess.actor(%{"librarian_of" => ""}) == %{visitor: nil, librarian_of: nil}
  end
end
