defmodule StatifierExamples.DescribeOutlineTest do
  @moduledoc """
  The library loan and patron registration described in words by
  `StatifierBlocks.Describe` under this app's palette: every block is a
  node exactly once, in the view model's outline order, and the lines that
  say how control passes between blocks are the ones the two charts mean.

  A few edge lines are pinned rather than the whole rendering: the lines a
  reader of either chart would check first (where the root starts, the
  interrupt rules, a branch arm, the step after an arm), so a change to an
  unrelated sentence does not re-pin this file.

  An edge line names a container by the package's noun for it ("the
  steps", "the group", "the branch"), and a step it names by that step's
  sentence, a delayed send's in double quotation marks; the node lines,
  the first of them the root's, keep each block's sentence.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.Block
  alias StatifierBlocks.Describe
  alias StatifierBlocks.Describe.Edge
  alias StatifierBlocks.Describe.Node
  alias StatifierBlocks.ViewModel
  alias StatifierExamples.Charts

  defp document(key) do
    {:ok, fixture} = Charts.fixture(key)
    fixture.document
  end

  defp outline(key), do: Describe.outline(document(key), Charts.palette(), [])

  defp block_ids(%Block{id: id, slots: slots}) do
    [id | slots |> Map.values() |> List.flatten() |> Enum.flat_map(&block_ids/1)]
  end

  defp interrupts(outline), do: for(%Edge{kind: :interrupt} = edge <- outline.edges, do: edge)

  # Sabotage: dropped the last node id from the outline before the comparison;
  # this went red on the library loan, the first domain it reads. Restored
  # from a copy.
  test "every block of both domains is a node exactly once, in outline order" do
    for key <- ["library_loan", "patron_registration"] do
      document = document(key)
      outline = outline(key)
      ids = for %Node{id: id} <- outline.nodes, do: id

      assert Enum.sort(ids) == Enum.sort(block_ids(document.root)), key
      assert ids == Enum.uniq(ids), key

      view_model = ViewModel.build(document, Charts.palette(), [])
      assert ids == for({node, _depth, _kind} <- ViewModel.outline(view_model), do: node.block_id)

      assert outline.id == document.id
      assert outline.revision == document.revision
    end
  end

  # Sabotage: changed the interrupt edge's verb in the dependency's
  # `Describe` from "abandons" to "leaves" and recompiled it; this went red
  # on the first interrupt line. Restored from a copy.
  #
  # 2026-09-29: an edge line names a container by the package's noun.
  # Sabotage: changed the dependency's noun for a group from "the group" to
  # "the region" and recompiled it; both cases went red, the library loan
  # on its first interrupt line and patron registration on the group's
  # first step. Then dropped the quotation marks the dependency sets round
  # a delayed send in an edge line; patron registration went red on the
  # group's first step. Each restored from a copy.
  test "the library loan reads as its chart" do
    outline = outline("library_loan")
    lines = Describe.render(outline, [])

    assert hd(lines) == "Run its steps in order"
    assert length(lines) == length(outline.nodes) + length(outline.edges)
    assert length(interrupts(outline)) == 2

    for line <- [
          "The steps start with Run interruptible steps",
          "On copy.returned, When copy.returned, abandon abandons the group",
          "On copy.reported_lost, When copy.reported_lost, abandon abandons the group",
          "The branch: when loan.returned, Send loan.closed",
          "After Send loan.overdue (done), Wait for copy.returned, giving up after 14d"
        ] do
      assert line in lines, line
    end
  end

  # The deadline ends the registration: the age branch and the welcome sit
  # inside the group's body, the group is the root's last step, and so the
  # rule that abandons the group ends the document.
  #
  # Sabotage: moved blk_pr_age and blk_pr_welcome back out after the group
  # in the fixture; this went red on the group ending the root. Restored
  # from a copy.
  test "patron registration reads as its chart" do
    outline = outline("patron_registration")
    lines = Describe.render(outline, [])

    assert hd(lines) == "Run its steps in order"
    assert length(lines) == length(outline.nodes) + length(outline.edges)
    assert length(interrupts(outline)) == 2

    for line <- [
          ~s|The group starts with "In 7 days, send registration.deadline"|,
          "Run interruptible steps (done) ends the steps",
          "On registration.deadline, When registration.deadline, abandon abandons the group",
          ~s|After Wait for email.verified (received, timed_out), Decide: When "child", otherwise|,
          ~s|After Decide: When "child", otherwise (done), Send patron.welcomed|,
          "Send patron.welcomed (done) ends the group",
          # The arm its author left empty goes straight to the branch's end.
          "The branch: otherwise, the end of the branch",
          "The branch: if undecided, Send patron.asked_to_visit",
          # The deadline send arms the rule that abandons the registration.
          "In 7 days, registration.deadline reaches When registration.deadline, abandon"
        ] do
      assert line in lines, line
    end
  end

  test "equal input answers the same lines" do
    for key <- ["library_loan", "patron_registration"] do
      assert Describe.render(outline(key), []) == Describe.render(outline(key), [])
    end
  end
end
