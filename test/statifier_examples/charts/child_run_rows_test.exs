defmodule StatifierExamples.Charts.ChildRunRowsTest do
  @moduledoc """
  A parent's feed says which of its rows are about a durable child run
  (se-0ay).

  A durable subchart runs as its own persisted run with a feed of its own,
  and the parent narrates only the moments it hands work over and the
  moment a hand-over is refused. Those rows used to be typographically
  identical to the parent's own work, so a reader watching a fan-out could
  not tell five things this run did from five children it started.
  """

  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  alias StatifierExamples.Charts.Run
  alias StatifierExamplesWeb.RunFeed

  describe "the reading" do
    # Sabotage: dropped the `source` key from `Run`'s appended entry map;
    # this went red with a KeyError on the first row read. Reverted from a
    # backup copy.
    test "a row carries the child run it is about, and the parent's own carry none" do
      run = reading()

      run =
        run
        |> Run.note(:started, "Run started", "run_parent")
        |> Run.note(
          :performed,
          "Child chart started",
          "bdoc_child as run run_parent-c0",
          "run_parent-c0"
        )

      assert [own, child] = Run.entries(run)

      assert own.source == nil
      assert child.source == "run_parent-c0"
    end
  end

  describe "the panel" do
    # Sabotage: removed the `:if={entry.source}` span from the What column;
    # both the chip text and the data attribute went missing and this went
    # red. Reverted from a backup copy.
    test "renders the child's id beside the row, and marks the row for the stylesheet" do
      run =
        reading()
        |> Run.note(:started, "Run started", "run_parent")
        |> Run.note(:performed, "Child chart started", "bdoc_child", "run_parent-c0")

      html =
        rendered_to_string(
          RunFeed.panel(%{
            id: "runs",
            count: nil,
            run: run,
            events: [],
            __changed__: nil
          })
        )

      assert html =~ ~s(data-run-source="run_parent-c0")
      assert html =~ "myapp-runs__source"
      assert html =~ "child run_parent-c0"

      # The parent's own row is not marked, which is the half that makes
      # the mark mean anything.
      refute html =~ ~s(<tr data-run-entry="started" data-run-source=)
    end
  end

  # A reading needs a machine and a provenance to name blocks, and neither
  # is exercised by a row the driver wrote: `note/5` appends what it is
  # given. So the struct is built directly rather than by compiling and
  # running a chart, which is the same reason `absorb/2` is tested by
  # feeding it effects.
  @spec reading() :: Run.t()
  defp reading do
    %Run{
      session_id: "run_parent",
      machine: nil,
      provenance: nil,
      labels: %{},
      events: []
    }
  end
end
