defmodule StatifierExamples.Charts.ChildRunRowsTest do
  @moduledoc """
  How a parent's reading of a run says anything about a durable child of
  it - the question `se-0ay` asked of the deleted feed, asked again of the
  Run pane the editor page took over in `se-dh0`.

  The answer changed shape rather than being lost, and where it now comes
  from is `statifier_persistence`'s ADR-0010 decision 7. A durable
  subchart's child is an ordinary run with an input log of its own, and
  nothing merges the two logs. What crosses between them is the child's
  ANSWER: it reaches the parent through `Driver.answer_parent/3`, which
  re-enters the parent through its own `done_invocation` door, so the
  answer is an entry on the parent's log - the input the parent's
  interpreter actually saw. The parent's pane therefore narrates its
  children by construction, with no join and no second stream, and it
  narrates exactly what the parent knew: that the call came back, and with
  what.

  What retired with the feed is the CHIP - the `child <run id>` span the
  panel drew beside a row, and the `data-run-source` attribute the
  stylesheet keyed on. The pane's log renders wire-format messages, and a
  message about an invocation answer carries the `invoke_id` rather than
  the child's run id, so there is nothing for a chip to say. The
  `entry.source` field `se-0ay` added to `StatifierExamples.Charts.Run`
  stays where it is and stays covered here: the driver still writes it,
  and it is still what a reader of a `%Run{}` reads.
  """

  # Not async: the second half drives a durable subchart, which steps
  # through the application's named `StatifierExamples.Charts.RunLock` and
  # writes to the repo.
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias StatifierExamples.Charts
  alias StatifierExamples.Charts.{Durable, Replay, Run, Subchart}
  alias StatifierExamples.Repo
  alias StatifierPersistence.Run.Linkage

  setup do
    :ok = Sandbox.checkout(Repo)

    %{run_id: "run-#{System.unique_integer([:positive])}"}
  end

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

  describe "the parent's replayed log" do
    # The criterion the pane took over from the feed: a parent whose child
    # has answered narrates the answer, out of the parent's own stored
    # inputs and nothing else.
    #
    # The assertion is on the ANSWER event rather than on a count of
    # entries, because the count is the parent's whole run and the answer is
    # the one entry that could only have come from the child. Its name
    # carries the invocation the child was started for, which is the join a
    # reader has: `blk_so_wizard` is the subchart block on the parent's
    # canvas.
    #
    # The parent's two rows are both at the `"answer_parent"` door, which is
    # what decision 5's table says and what this app's driver produces: the
    # subchart's answer and, behind it, the child's own asynchronous call
    # answering the child.
    #
    # Sabotage: mapped every `"answer_parent"` row to `{:event, ...}` instead
    # of `{:invoked_event, ...}` - the mapping error decision 8 warns about
    # by name. This test STAYED GREEN, and so did the whole replay: 60
    # messages, byte for byte the same stream. That is recorded rather than
    # papered over, because it says what the mapping is worth here. The event
    # carries its own `invokeid` and the parent's transitions select on the
    # event's NAME, so this particular chart replays identically under either
    # entry shape; what the shape decides is whether the replay's live
    # invocation set is kept, which shows up in a chart that reads that set
    # (an `autoforward`, a `cancel_invoke` against a still-live id) and not
    # in this one. The mapping follows the record because the record is the
    # contract, not because this test could tell.
    test "holds the child's answer, at the door the child re-entered by", %{run_id: run_id} do
      {:ok, parent} = Charts.fixture("signup_onboarding")
      {:ok, compiled} = Durable.compile(parent.document, parent.declare)
      {:ok, _driven} = Durable.start(compiled, parent.document, run_id, "signup_onboarding")

      finish_child!(run_id)

      {:ok, machine} = Statifier.compile(compiled.scxml)
      {:ok, messages} = Replay.messages(run_id, machine)

      assert Enum.any?(messages, &answered?(&1, "blk_so_wizard"))
    end

    # The other half of decision 7, and the half that makes the first one
    # mean something: the parent's log holds the child's answer and NOT the
    # child's own inputs. A reader who wants those reads the child's log,
    # which is its own run's.
    #
    # Sabotage: none available - this asserts an absence the seam produces
    # rather than a value this app computes. It is here as the statement of
    # the boundary, and `replay_test.exs` is where the mapping itself is
    # driven.
    test "does not hold the child's own inputs", %{run_id: run_id} do
      {:ok, parent} = Charts.fixture("signup_onboarding")
      {:ok, compiled} = Durable.compile(parent.document, parent.declare)
      {:ok, _driven} = Durable.start(compiled, parent.document, run_id, "signup_onboarding")

      finish_child!(run_id)

      {:ok, machine} = Statifier.compile(compiled.scxml)
      {:ok, messages} = Replay.messages(run_id, machine)

      refute Enum.any?(messages, &names_event?(&1, "statifier_blocks.wait.blk_su_verify_wait"))
    end
  end

  describe "the hybrid fan-out's parent" do
    # The bead's own criterion, on the fixture it names - and the answer it
    # gets is worth stating precisely, because it is not the one the
    # criterion's wording suggests.
    #
    # A `core.map` fan-out is ONE invocation of the parent's, not ten. Ten
    # children run, each as its own persisted run with its own log, and the
    # package's settlement assembles their outcomes and answers the parent's
    # single invocation once, at the `answer_parent` door. So what the
    # parent's replayed log narrates is `done.invoke.blk_bi_chunks` - the
    # fan-out coming back - and what that answer CARRIES is the ten results,
    # which is why both are asserted here. Ten rows about ten children were
    # the deleted feed's reading, written by this app; the pane's reading is
    # the parent's own inputs, and the parent had one.
    #
    # Sabotage: mapped the `"answer_parent"` door to `{:error, ...}` instead
    # of an entry; the replay refused outright and this went red on the
    # `{:ok, messages}` match. Reverted from a backup copy.
    test "narrates the fan-out's answer, which is one invocation and not ten",
         %{run_id: run_id} do
      {:ok, fixture} = Charts.fixture("signup_bulk_invites")
      {:ok, compiled} = Durable.compile(fixture.document, fixture.declare)
      {:ok, _driven} = Durable.start(compiled, fixture.document, run_id, "signup_bulk_invites")

      assert %{success: 1} = Oban.drain_queue(queue: Charts.AsyncCalls.queue())
      assert %{success: 10} = Oban.drain_queue(queue: Charts.AsyncCalls.queue())

      {:ok, machine} = Statifier.compile(compiled.scxml)
      {:ok, messages} = Replay.messages(run_id, machine)

      assert Enum.any?(messages, &answered?(&1, "blk_bi_chunks"))

      results = Durable.machine_state(run_id) |> elem(1) |> Map.fetch!(:datamodel)

      assert length(Map.fetch!(results, "results")) == 10
    end
  end

  # Drives the child of `run_id` to its own end, cold, the way
  # `DurableTest` does: the child is an ordinary run, so it resumes by id
  # and answers its parent through the driver rather than through anything
  # this test calls.
  defp finish_child!(run_id) do
    {:ok, child} = Charts.fixture("signup_wizard")
    {:ok, child_compiled} = Subchart.child_compile(child.document)
    child_run_id = Linkage.child_run_id(run_id, "blk_so_wizard", 0)

    {:ok, {child_durable, child_run}} =
      Durable.resume(child_compiled, child.document, child_run_id)

    {:ok, {_durable, _run}} =
      Durable.send_event(child_durable, child_run, "statifier_blocks.wait.blk_su_verify_wait")

    %{success: 1} = Oban.drain_queue(queue: Charts.AsyncCalls.queue())

    :ok
  end

  # The child's answer as the parent's interpreter saw it: the event it
  # dequeued, named for the invocation the subchart block was started
  # under and carrying that block's `invokeid`. Both halves are checked,
  # because the name alone is a string the chart also mentions in its
  # transitions and the manifest carries those verbatim.
  defp answered?(%{type: "trace.event_dequeued", payload: payload}, invoke_id) do
    case payload do
      %{"event" => %{"name" => name, "invokeid" => ^invoke_id}} ->
        name == "done.invoke." <> invoke_id

      _other ->
        false
    end
  end

  defp answered?(_message, _invoke_id), do: false

  defp names_event?(%{payload: %{"event" => %{"name" => name}}}, name), do: true
  defp names_event?(_message, _name), do: false

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
