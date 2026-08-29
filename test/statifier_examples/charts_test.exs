defmodule StatifierExamples.ChartsTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.Palette
  alias StatifierExamples.Charts

  # Sabotage: pointed palette/0 at Palette.new(); the core.sequence assertion
  # went red, then reverted.
  test "the palette is statifier_blocks' core vocabulary" do
    assert %Palette{types: types} = Charts.palette()
    assert Map.has_key?(types, "core.sequence")
  end

  # Sabotage: dropped :brand from @themes; this went red, then reverted.
  test "the host offers three theme tokens" do
    assert Charts.themes() == [:light, :dark, :brand]
  end

  # Sabotage: made icon/1 return the name it was given; this went red, then
  # reverted.
  test "the icon seam resolves nothing yet" do
    assert Charts.icon("core.sequence") == nil
    assert Charts.icon(:compile) == nil
  end

  # Sabotage: seeded fixtures/0 with a placeholder list; this went red, then
  # reverted.
  test "no fixture documents are registered yet" do
    assert Charts.fixtures() == []
  end
end
