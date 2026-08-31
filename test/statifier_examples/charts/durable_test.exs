defmodule StatifierExamples.Charts.DurableTest do
  # Not async: durable runs step through the application's own
  # `StatifierExamples.Charts.RunLock`, which is named, shared state, and
  # they write to the repo.
  use ExUnit.Case, async: false

  import Ecto.Query, only: [from: 2]

  alias Ecto.Adapters.SQL.Sandbox
  alias StatifierBlocks.{Compiler, Decode}
  alias StatifierExamples.Charts
  alias StatifierExamples.Charts.{Durable, Run}
  alias StatifierExamples.Repo
  alias StatifierExamples.Signup.{Accounts, User}
  alias StatifierPersistence.{Runs, Storage}

  # Where the signup wizard parks itself: its verification group is waiting
  # on the 24-hour `core.wait`, with both interrupts armed. This is the
  # mid-flight configuration the restart walkthrough kills the server in.
  @waiting ["blk_su_abandoned", "blk_su_verified", "blk_su_verify_wait"]

  setup do
    :ok = Sandbox.checkout(Repo)

    %{run_id: "run-#{System.unique_integer([:positive])}"}
  end

  defp compile!(document) do
    {:ok, compiled} =
      Compiler.compile(document, Charts.palette(), known_invoke_types: Charts.invoke_types())

    compiled
  end

  defp signup do
    {:ok, fixture} = Charts.fixture("signup_wizard")

    {compile!(fixture.document), fixture.document}
  end

  # A one-block document, built here rather than added to `priv/fixtures`,
  # because what it is for is reaching `myapp:provision` in two steps. The
  # shipped signup wizard cannot: its plan branch reads `signup.plan` and
  # `signup.seats` from a datamodel the document does not declare, so every
  # run of it takes the `otherwise` arm and abandons before provisioning.
  defp provisioning do
    {:ok, document} =
      Decode.decode("""
      {
        "schema_version": 1,
        "id": "bdoc_provision_only",
        "revision": 1,
        "metadata": {"name": "Provision only", "domain": "signup"},
        "root": {
          "type": "core.sequence",
          "id": "blk_po_root",
          "type_version": 1,
          "slots": {
            "body": [
              {
                "type": "myapp.provision",
                "id": "blk_po_provision",
                "type_version": 1,
                "config": {"invoke_type": "myapp:provision", "label": "Create the workspace"}
              }
            ]
          }
        }
      }
      """)

    {compile!(document), document}
  end

  defp store! do
    {:ok, store} = Storage.new(StatifierExamples.Persistence, [])

    store
  end

  defp record!(run_id) do
    {:ok, record} = Storage.fetch_run(store!(), run_id)

    record
  end

  defp kinds(run), do: run |> Run.entries() |> Enum.map(& &1.kind)

  defp details(run), do: run |> Run.entries() |> Enum.map(& &1.detail)

  defp accounts(run_id) do
    email = Accounts.email_for(run_id)

    Repo.one!(from(u in User, where: u.email == ^email, select: count()))
  end

  # The constraint this whole module is shaped around, asserted rather than
  # described: `StatifierExamples.Persistence` declines `lock_run/3`, so
  # `StatifierPersistence.Runs`' default serialization refuses before a run
  # can start. Every entry point in `Durable` passes a strategy for exactly
  # this reason, and if the default ever started working here that is a
  # thing to find out from a test rather than from a silent change.
  #
  # Sabotage: made `StatifierExamples.Persistence` delegate `lock_run/3` to
  # the Ecto adapter; this went red - with `no such function:
  # hashtextextended` out of SQLite - then reverted.
  test "the default serialization strategy refuses over this adapter", %{run_id: run_id} do
    {compiled, _document} = signup()
    {:ok, machine} = Statifier.compile(compiled.scxml)

    assert {:error, {:serialization, :not_supported}} =
             Runs.create(store!(), run_id, machine, executor: fn _effect, _ctx -> :ok end)
  end

  # Sabotage: made `Durable.start/3` create the run without its
  # `initialize: [trace: true]`, so no trace effect reached the reading;
  # this went red on the marks, then reverted.
  test "a started run is durable: a record, a position, and a status", %{run_id: run_id} do
    {compiled, document} = signup()

    assert {:ok, {_durable, run}} = Durable.start(compiled, document, run_id)
    assert run.status == :running
    assert run.active == @waiting

    record = record!(run_id)

    assert record.status == :active
    assert is_binary(record.position_blob)
    assert record.content_hash =~ "sha256:"
  end

  # The restart, in one process: a run driven to its wait, then picked back
  # up by a `resume/3` that shares nothing with the driver that started it
  # but the run id and the document. The marks have to come back, because
  # they are what a reader sees on the canvas after a reload.
  #
  # Sabotage: made `resume/3` skip its `MacrostepStable` fold, so the
  # loaded position was never read into the marks; this went red on
  # `resumed.active`, then reverted.
  test "a stored run resumes with the configuration it was left on", %{run_id: run_id} do
    {compiled, document} = signup()

    {:ok, {_durable, run}} = Durable.start(compiled, document, run_id)

    assert {:ok, {_driver, resumed}} = Durable.resume(compile!(document), document, run_id)

    assert resumed.active == run.active
    assert resumed.status == :running
    assert [%{kind: :started, label: "Run resumed from storage"}] = Run.entries(resumed)
  end

  # And it keeps going: a resumed run steps on the next press exactly as
  # the one that created it would have.
  #
  # Sabotage: made `resume/3` build its `Durable` struct with a freshly
  # generated run id; this went red - `:run_not_found` out of the step -
  # then reverted.
  test "a resumed run continues from storage", %{run_id: run_id} do
    {compiled, document} = signup()
    {:ok, {_durable, _run}} = Durable.start(compiled, document, run_id)
    {:ok, {durable, run}} = Durable.resume(compile!(document), document, run_id)

    assert {:ok, {_driver, stepped}} =
             Durable.send_event(durable, run, "statifier_blocks.wait.blk_su_verify_wait")

    assert stepped.active == ["blk_su_root"]
    assert :event in kinds(stepped)
  end

  # A run id nobody stored is an answer, not a crash - the page shows it.
  test "resuming a run that was never stored is refused", %{run_id: run_id} do
    {_compiled, document} = signup()

    assert {:error, :run_not_found} = Durable.resume(compile!(document), document, run_id)
  end

  # Sabotage: made `abandon/1` call `Runs.fail/4` with the default
  # serialization; this went red - `{:serialization, :not_supported}` left
  # the record `:active` - then reverted.
  test "abandoning a run marks the record failed and keeps its position", %{run_id: run_id} do
    {compiled, document} = signup()
    {:ok, {durable, _run}} = Durable.start(compiled, document, run_id)
    stored = record!(run_id)

    assert :ok = Durable.abandon(durable)

    record = record!(run_id)

    assert record.status == :failed
    assert record.failure == "host:stopped"
    assert record.position_blob == stored.position_blob
  end

  # Sabotage: dropped the `%{run_id: run_id}` context from the driver's
  # dispatch, so the handler took its run-less clause; this went red on the
  # row count, then reverted.
  test "myapp:provision writes the account row for the run", %{run_id: run_id} do
    {compiled, document} = provisioning()

    assert {:ok, {_durable, run}} = Durable.start(compiled, document, run_id)

    assert accounts(run_id) == 1

    # The chart reaches its root outcome and rests there rather than
    # finishing: a compiled block document carries no top-level `<final>`,
    # so `Statifier.Interpreter` never emits `:done` and
    # `StatifierPersistence.Runs` never has a `:completed` to write. That
    # is recorded here rather than worked around - the finding belongs
    # upstream in `statifier_blocks`, and asserting what is true is what
    # makes the day it changes visible.
    assert run.status == :running
    assert run.active == ["blk_po_root"]
    assert record!(run_id).status == :active
  end

  # The feed is where a reader learns the write happened and which way it
  # went, so the row carries both the address and the answer.
  #
  # Sabotage: made the driver's `performed/2` print only the invoke type;
  # this went red, then reverted.
  test "the run feed says what the provisioning call did", %{run_id: run_id} do
    {compiled, document} = provisioning()
    {:ok, {_durable, run}} = Durable.start(compiled, document, run_id)

    assert :performed in kinds(run)

    assert Enum.any?(details(run), fn detail ->
             is_binary(detail) and detail =~ "myapp:provision" and detail =~ "created" and
               detail =~ Accounts.email_for(run_id)
           end)
  end

  # At-least-once is the executor's contract, so a second delivery of one
  # call is an ordinary event and not a second account. Delivering it by
  # hand - the same `Charts.dispatch/3` the driver makes - is the honest
  # way to test a replay without staging a crash.
  #
  # Sabotage: made `Accounts.provision/1` insert without `on_conflict`;
  # this went red with an `Exqlite.Error`, then reverted.
  test "a replayed provisioning call does not write a second row", %{run_id: run_id} do
    {compiled, document} = provisioning()
    {:ok, {_durable, _run}} = Durable.start(compiled, document, run_id)

    assert {:ok, %{"provisioned" => "existing"}} =
             Charts.dispatch("myapp:provision", %{}, %{run_id: run_id})

    assert accounts(run_id) == 1
  end

  # Chart identity is what stops a run resuming onto a document that has
  # been edited underneath it, and the guard is the storage layer's rather
  # than this app's - this asserts the app surfaces it instead of eating it.
  #
  # Sabotage: made `resume/3` skip `load_run_position/3` and build the
  # reading from the record alone; this went red - the mismatch was never
  # noticed - then reverted.
  test "resuming onto a different document is refused", %{run_id: run_id} do
    {compiled, document} = signup()
    {:ok, {_durable, _run}} = Durable.start(compiled, document, run_id)

    {other_compiled, other_document} = provisioning()

    assert {:error, {:identity_mismatch, _stored, _supplied}} =
             Durable.resume(other_compiled, other_document, run_id)
  end
end
