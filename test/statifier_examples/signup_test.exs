defmodule StatifierExamples.SignupTest do
  use ExUnit.Case, async: true

  alias StatifierExamples.Signup

  # Sabotage: made block_types/0 return a non-empty map; this went red, then
  # reverted.
  test "the seam starts with no registered block types" do
    assert Signup.block_types() == %{}
  end
end
