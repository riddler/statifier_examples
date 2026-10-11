defmodule StatifierExamples.RouterKeyTest do
  @moduledoc """
  The one spelling of the router's key that the routed recipe's route and
  the card application form's two routes store.
  """

  use ExUnit.Case, async: true

  alias StatifierExamples.RouterKey

  doctest RouterKey

  @position %{send_id: nil, macrostep: 4, microstep: 2, round: 1, c_index: nil, owner: nil}

  # Sabotage: spelled an absent ordinal as the empty string in
  # `RouterKey.join/1`; this went red at the second match. Reverted from a
  # copy.
  test "the key joins the scope, the step position and the ordinal" do
    assert "ex_parcel_9:4:2:1:7" = RouterKey.join({"ex_parcel_9", @position, 7})
    assert "ex_parcel_9:4:2:1:-" = RouterKey.join({"ex_parcel_9", @position, nil})
  end
end
