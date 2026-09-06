defmodule StatifierExamples.Signup.InvitesTest do
  @moduledoc """
  The data plane's own write: the rows a chunk descriptor stands for, and
  the at-least-once property the `{chunk_id, email}` index buys (se-j87).
  """

  # Not async: writes to the repo.
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias StatifierExamples.Repo
  alias StatifierExamples.Signup.Invites

  setup do
    :ok = Sandbox.checkout(Repo)

    :ok
  end

  # A descriptor stands for a row set and is not one. Asserted on the
  # derivation rather than on a stored list, because the derivation is
  # what makes the write idempotent.
  #
  # Sabotage: made `rows_for/1` answer `{:ok, []}` for an unrecognised
  # descriptor instead of `:error`; this went red on the last assertion.
  # Reverted.
  test "a descriptor derives its rows, and an unrecognised one is refused" do
    assert {:ok, emails} = Invites.rows_for("su-c01")
    assert length(emails) == 25
    assert hd(emails) == "invitee-su-c01-1@example.com"
    assert Enum.all?(emails, &String.ends_with?(&1, "@example.com"))

    assert :error = Invites.rows_for("su-cXX")
    assert :error = Invites.rows_for("su-c11")
    assert :error = Invites.rows_for("")
  end

  # Exactly one invitee across the ten chunks needs chart semantics, and
  # which one is a fact about the descriptor rather than a value invented
  # when the chunk runs.
  #
  # Sabotage: made `promoted_email/1` answer for every chunk; this went
  # red on the count. Reverted.
  test "one invitee across the ten chunks is the promoted one" do
    promoted =
      for n <- 1..10, chunk = "su-c#{String.pad_leading("#{n}", 2, "0")}" do
        Invites.promoted_email(chunk)
      end

    assert Enum.count(promoted, &is_binary/1) == 1
    assert Invites.promoted_email("su-c07") == "invitee-su-c07-3@example.com"
    assert Invites.promoted_run_id("su-c07") == "promoted-su-c07"
  end

  # The at-least-once property, measured rather than argued: the same
  # chunk recorded twice is one row set, because the upsert conflicts on
  # the index the migration created.
  #
  # Sabotage: dropped `on_conflict: :nothing` from `record/3`; this went
  # red with a raised `Exqlite.Error` on the second call. Reverted.
  test "recording the same chunk twice writes one row set" do
    assert {:ok, 25} = Invites.record("su-c01", "run-1", nil)
    assert Invites.count() == 25

    assert {:ok, 25} = Invites.record("su-c01", "run-1", nil)
    assert Invites.count() == 25
  end

  # The promoted row is the only one carrying a run of its own, and it
  # carries the run id the writer was handed rather than one derived a
  # second time.
  #
  # Sabotage: made `promoted_for/3` return the run id for every row; this
  # went red on the promoted count. Reverted.
  test "only the promoted row carries a run of its own" do
    assert {:ok, 25} = Invites.record("su-c07", "run-7", "promoted-su-c07")

    rows = Invites.for_chunk("su-c07")
    assert length(rows) == 25

    assert [promoted] = Invites.promoted()
    assert promoted.email == "invitee-su-c07-3@example.com"
    assert promoted.status == "promoted"
    assert promoted.promoted_run_id == "promoted-su-c07"
    assert promoted.run_id == "run-7"

    assert Enum.count(rows, &(&1.status == "provisioned")) == 24
  end

  # A refused descriptor writes nothing at all, rather than writing what
  # it could and reporting a partial batch.
  #
  # Sabotage: made `record/3` fall through to the write for an
  # unrecognised descriptor; this went red on the count. Reverted.
  test "a refused descriptor writes nothing" do
    assert :error = Invites.record("su-cXX", "run-x", nil)
    assert Invites.count() == 0
  end
end
