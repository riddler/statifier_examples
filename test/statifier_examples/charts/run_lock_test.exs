defmodule StatifierExamples.Charts.RunLockTest do
  use ExUnit.Case, async: true

  alias StatifierExamples.Charts.RunLock

  setup do
    lock = start_supervised!({RunLock, name: :"lock-#{System.unique_integer([:positive])}"})

    %{lock: lock}
  end

  # Two bodies for one run id, started at the same moment, must not
  # overlap: the first records its entry and exit before the second records
  # its entry. The marks are drained IN ORDER - `assert_received` scans the
  # whole mailbox and would pass on an interleaved run - so the assertion
  # is on the sequence, which is the whole guarantee.
  #
  # Sabotage: made `handle_call({:acquire, _}, ...)` reply `:ok` for a run
  # id already held instead of enqueueing; the marks came back
  # `first_in, second_in, second_out, first_out` and this went red, then
  # reverted.
  test "two bodies for one run id never overlap", %{lock: lock} do
    marks = self()

    first =
      Task.async(fn ->
        RunLock.with_run(lock, "run", fn ->
          send(marks, :first_in)
          Process.sleep(50)
          send(marks, :first_out)
        end)
      end)

    # Started after the first has certainly taken the lock, so "the second
    # waited" is what the ordering below actually shows.
    Process.sleep(10)

    second =
      Task.async(fn ->
        RunLock.with_run(lock, "run", fn ->
          send(marks, :second_in)
          send(marks, :second_out)
        end)
      end)

    Task.await(first)
    Task.await(second)

    assert drain(4) == [:first_in, :first_out, :second_in, :second_out]
  end

  # The mailbox, in arrival order.
  defp drain(0), do: []

  defp drain(n) do
    receive do
      mark -> [mark | drain(n - 1)]
    after
      1_000 -> [:timeout]
    end
  end

  # Different run ids are exactly what the keying buys, so a body holding
  # one id must not delay a body on another.
  #
  # Sabotage: made `handle_call({:acquire, _}, ...)` key every lock on a
  # single constant instead of the run id; this went red on the timeout,
  # then reverted.
  test "two run ids run concurrently", %{lock: lock} do
    marks = self()

    held =
      Task.async(fn ->
        RunLock.with_run(lock, "one", fn ->
          send(marks, :holding)
          assert_receive :release, 1_000
        end)
      end)

    assert_receive :holding, 1_000

    assert {:ok, :ran} = RunLock.with_run(lock, "two", fn -> :ran end)

    send(held.pid, :release)
    Task.await(held)
  end

  # The body's value comes back inside the strategy's own envelope, which
  # is what `StatifierPersistence.Runs` unwraps.
  #
  # Sabotage: made `with_run/3` return the bare `fun.()`; this went red,
  # then reverted.
  test "the body's value comes back in the strategy envelope", %{lock: lock} do
    assert RunLock.with_run(lock, "run", fn -> {:ok, :whatever} end) == {:ok, {:ok, :whatever}}
  end

  # A holder that dies mid-body must hand the lock on rather than strand
  # the run id, because the holder here is usually a page.
  #
  # Sabotage: dropped the `Process.monitor/1` call in `grant/3`, so no
  # `:DOWN` ever arrived; this went red on the timeout, then reverted.
  test "a holder that dies releases the lock", %{lock: lock} do
    marks = self()

    holder =
      spawn(fn ->
        RunLock.with_run(lock, "run", fn ->
          send(marks, :holding)
          Process.sleep(:infinity)
        end)
      end)

    assert_receive :holding, 1_000
    Process.exit(holder, :kill)

    assert {:ok, :ran} = RunLock.with_run(lock, "run", fn -> :ran end)
  end

  # A body that raises must still release: the `after` clause is what makes
  # the exclusion safe to put a real stepper tail inside.
  #
  # Sabotage: replaced the `try/after` with a plain call/release pair; this
  # went red on the second acquire timing out, then reverted.
  test "a body that raises releases the lock", %{lock: lock} do
    assert_raise RuntimeError, fn ->
      RunLock.with_run(lock, "run", fn -> raise "boom" end)
    end

    assert {:ok, :ran} = RunLock.with_run(lock, "run", fn -> :ran end)
  end
end
