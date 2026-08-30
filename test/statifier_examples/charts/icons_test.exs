defmodule StatifierExamples.Charts.IconsTest do
  use ExUnit.Case, async: true

  alias StatifierExamples.Charts.Icons

  # The outline set, specifically. Solid heroicons ship the same names with
  # the same shape of markup, so "it is an svg body" cannot tell the two sets
  # apart - only the stroke attributes can, and a page that quietly swapped
  # to solid would be a visual change nothing else here would catch.
  #
  # Sabotage: pointed @outline_dir at the 24/solid directory; this went red on
  # both stroke assertions, then reverted.
  test "a glyph is an outline svg body and not a whole svg document" do
    body = Icons.body("clock")

    assert is_binary(body)
    assert body =~ "<path"
    assert body =~ ~s(stroke-linecap="round")
    refute body =~ "fill-rule"
    refute body =~ "<svg"
    refute body =~ "</svg>"
  end

  # Sabotage: made body/1 raise on an unknown name; this went red, then
  # reverted.
  test "an unknown name is nil rather than a raise" do
    assert Icons.body("no-such-heroicon") == nil
    assert Icons.body(:clock) == nil
    refute Icons.known?("no-such-heroicon")
    refute Icons.known?(nil)
  end

  # The set is read off disk at compile time, so this asserts the shape of
  # what was read rather than a transcription of it: sorted, non-trivial, and
  # carrying the names the example domains actually declare.
  #
  # Sabotage: made known_names/0 return Map.keys/1 unsorted; this went red,
  # then reverted.
  test "the known names are the outline set, sorted" do
    names = Icons.known_names()

    assert names == Enum.sort(names)
    assert length(names) > 100
    assert "credit-card" in names
    assert "clock" in names
  end
end
