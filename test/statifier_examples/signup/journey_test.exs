defmodule StatifierExamples.Signup.JourneyTest do
  @moduledoc """
  The Journey loop end to end: the Path as a durable execution, three submits, a
  screen nobody answers, and the create-account call the execution ends on.

  Not async: durable executions step through the application's named
  `StatifierExamples.Charts.ExecutionLock`, and the timers are rows.

  ## The acceptance line, and where it could not be met literally

  `se-7wt` asks for "an end-to-end test [that] drives three submits and one
  timeout through the durable execution". Three submits and one timeout cannot
  share an execution here: the Path has three screens, a timed-out screen is by
  definition one that was **not** submitted, and an execution that took all three
  buttons has finished before any deadline can elapse. So the end-to-end
  obligation is met by two executions in this module - "three submits" below, and
  "a screen nobody answers" beside it - and the divergence is recorded here
  rather than papered over by a test that drives both in one function and
  calls itself one execution.
  """

  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias StatifierExamples.Charts.{AsyncCalls, Durable, Timers}
  alias StatifierExamples.Repo
  alias StatifierExamples.Signup.{Journey, Screens}

  @account %{"first_name" => "Ada", "email" => "ada@example.com"}

  setup do
    :ok = Sandbox.checkout(Repo)

    {:ok, execution_id} = Journey.start("journey-#{System.unique_integer([:positive])}")

    %{execution_id: execution_id}
  end

  defp key(%{screen: nil}), do: nil
  defp key(%{screen: screen}), do: screen.key

  defp keys(%{nodes: nodes}), do: Enum.map(nodes, & &1["key"])

  # Everything an execution's own reader can see of it, loaded the way a page
  # loads it: from the id and nothing else.
  defp seen(execution_id) do
    {:ok, view} = Journey.current(execution_id)

    view
  end

  describe "the run starts on the first screen" do
    test "and the screen is resolved against an empty datamodel", %{execution_id: execution_id} do
      view = seen(execution_id)

      assert key(view) == "account"
      assert view.status == :running
      assert view.responses == %{}

      # `account_greeting` is conditional on a name nobody has given yet.
      assert keys(view) == [
               "account_heading",
               "account_intro",
               "first_name",
               "email",
               "account_continue"
             ]
    end

    # Sabotage: made `Journey.screen_at/1` look for the composite block's own
    # id instead of `Screen.park_block_id/1`'s. EIGHTEEN cases went red
    # across this module and the page's - no view ever finds a screen - which
    # is the right blast radius for the one thing the loop rests on. This
    # case was not among them: an execution that does not exist has no screen to
    # miss. Reverted from a copy.
    test "a run id nobody stored is a refusal, not an empty page" do
      assert Journey.current("no-such-execution") == {:error, :execution_not_found}
    end
  end

  describe "current/1 walks storage once" do
    # se-w4i, asserted by counting rather than by reading the source. Every
    # read of the execution row goes through `StatifierExamples.Repo`, so
    # Ecto's own query telemetry is the seam, and it is a cheap one: attach,
    # resolve one view, count what the test process issued.
    #
    # TWO, not one, and the difference is worth stating because it is the
    # part se-w4i does not claim. One `Durable.resume/1` reads the record
    # once - to pick the chart and to open the reading on the stored status,
    # off the same row - and the position load reads it a second time. Those
    # two belong to one resume and are that function's own business. It was
    # THREE until the record fetch inside `resume/3` was collapsed into the
    # one `resume/1` already does. What this case pins is that `current/1`
    # resolves the execution ONCE: before se-w4i it resumed for the reading
    # and then walked storage a second time through `Durable.machine_state/1`
    # for the datamodel, and the count here was FIVE.
    #
    # Sabotage: restored the second `Storage.fetch_execution/2` inside
    # `Durable.resume/3`'s `with` (the shape this test pinned at 3). This
    # case went red at 3 reads and nothing else moved - the extra read
    # returns the row `resume/1` already holds, which is exactly why it was
    # invisible until it was counted. Reverted from a copy.
    test "reading and datamodel come out of the same load", %{execution_id: execution_id} do
      assert reads_during(fn -> assert {:ok, _view} = Journey.current(execution_id) end) == 2
    end

    # Queries issued by this process, against the execution table, while
    # `work` runs. The pid filter keeps Oban's own pollers out of the count.
    defp reads_during(work) do
      owner = self()
      handler = "se-w4i-#{System.unique_integer([:positive])}"

      :ok =
        :telemetry.attach(
          handler,
          [:statifier_examples, :repo, :query],
          fn _event, _measurements, %{source: source}, ^owner ->
            if self() == owner and source == "statifier_executions" do
              send(owner, {:execution_read, handler})
            end
          end,
          owner
        )

      try do
        work.()
      after
        :telemetry.detach(handler)
      end

      drain_reads(handler, 0)
    end

    defp drain_reads(handler, count) do
      receive do
        {:execution_read, ^handler} -> drain_reads(handler, count + 1)
      after
        0 -> count
      end
    end
  end

  describe "three submits" do
    # THE END-TO-END CASE. Three presses, each one a cold load from storage,
    # and what comes back at the end is the receipt the create-account call
    # answered with. The seat count decides the branch: one seat is the
    # personal arm, which this app answers synchronously.
    #
    # se-luu (RQ-RF046-4, 2026-09-13): the plan press below carries the typed
    # seat count and NOTHING ELSE - no `plan` field, and `plan_personal`
    # declares no `payload` map for one to be merged in from. `responses.plan`
    # still comes back `"personal"`, because the button's capture pair is the
    # literal `["const", "personal"]` and the compiled assign writes it out of
    # the document. That is the acceptance this case carries.
    #
    # Sabotage, re-run at se-luu: made `pressed/5` send the outcome event with
    # no payload at all (`Durable.send_event/4`'s default). THREE cases went
    # red - this one at its first assertion about `responses`, where the
    # account screen's two questions came back `%{}` - because the QUESTION
    # pairs are still string sources and nothing the form collected was
    # written. The note here used to record FIVE; the two it no longer reaches
    # were the ones the old note described as only wanting an execution
    # somewhere down the business arm, and the reason is that the plan branch
    # now survives the mutation - which is exactly what the literal form
    # bought. Reverted from a copy.
    test "drive the run from the first screen to the created account", %{
      execution_id: execution_id
    } do
      assert {:ok, plan} = Journey.submit(execution_id, "account_submitted", @account)
      assert key(plan) == "plan"
      assert plan.responses == %{"first_name" => "Ada", "email" => "ada@example.com"}

      assert {:ok, confirm} = Journey.submit(execution_id, "personal_chosen", %{"seats" => "1"})
      assert key(confirm) == "confirm"
      assert confirm.responses["plan"] == "personal"

      # Coerced on the way in, which is what lets the confirm screen's
      # conditional half stay off for a one-seat signup.
      assert confirm.responses["seats"] == 1
      assert keys(confirm) == ["confirm_heading", "confirm_summary", "confirm_finish"]

      # The paragraph reads back the address the first screen collected,
      # through the chart rather than through the socket.
      assert Enum.find(confirm.nodes, &(&1["key"] == "confirm_summary"))["text"] =~
               "ada@example.com"

      assert {:ok, done} = Journey.submit(execution_id, "signup_confirmed", %{})
      assert done.status == :done
      assert key(done) == nil

      # The stub create-account call, and the proof it was handed the
      # responses rather than a step name: it echoes the address back.
      # Four, not the five this counted before `statifier_blocks` 0.28.0.
      # `collected` is `map_size(responses)`, and the confirm screen demands
      # nothing, so its own capture pair has no source in `_event.data`.
      # Under sb-ADR-0002's capture Note (N2) that pair now leaves its
      # destination UNWRITTEN, where it used to write the interpreter's
      # `:undefined` into it and be counted. The four that remain are the
      # two the account screen collected, the plan the button recorded and
      # the coerced seat count - measured, not relaxed.
      assert done.responses == %{
               "first_name" => "Ada",
               "email" => "ada@example.com",
               "plan" => "personal",
               "seats" => 1
             }

      assert done.datamodel["created"] == %{
               "created" => true,
               "email" => "ada@example.com",
               "collected" => 4
             }
    end

    # The other arm, and the shape se-d74 built: more than one seat is the
    # business plan, whose company-details step this app runs as an Oban job.
    # The execution rests durably in the middle of the call - no screen, no
    # process, a live invocation - and the job's answer is what moves it on.
    #
    # Sabotage (se-luu, 2026-09-13): reverted `plan_business`'s `writes` pair
    # in `priv/fixtures/signup_screens.json` to the string form
    # `{"responses.plan": "plan"}` from a copy. This case went red on the
    # `screen: nil` rest: with no `payload` map on the button and no path in
    # the pressed event to read, `responses.plan` was never written, the
    # branch took neither arm, and no call was ever made. Reverted from the
    # copy. (The sabotage this note used to carry - making `payload/2` ignore
    # the button's own declared map - is not a mutation any more: se-bzx
    # dropped that merge, and `payload/2` is covered directly below.)
    test "the business arm rests durably on an asynchronous call", %{execution_id: execution_id} do
      {:ok, _plan} = Journey.submit(execution_id, "account_submitted", @account)

      assert {:ok, mid_call} = Journey.submit(execution_id, "business_chosen", %{"seats" => "5"})
      assert key(mid_call) == nil
      assert mid_call.status == :running
      assert mid_call.responses["plan"] == "business"

      assert %{success: 1} = Oban.drain_queue(queue: AsyncCalls.queue())

      resumed = seen(execution_id)
      assert key(resumed) == "confirm"

      # Five seats turns the confirm screen's conditional half on.
      assert "referral" in keys(resumed)

      assert {:ok, done} =
               Journey.submit(execution_id, "signup_confirmed", %{"referral" => "A colleague"})

      assert done.status == :done
      assert done.datamodel["created"]["created"] == true
    end
  end

  describe "the run parks between screens" do
    # "No process alive" in the only sense that can be asserted: nothing in
    # this app holds a parked execution. A `Statifier.Session` would be registered
    # under the engine's own registry (st-ADR-0027) and there is none, and
    # the view a page draws carries no pid of any kind.
    #
    # No sabotage: this case asserts an absence, so there is nothing in
    # `lib/` to break that would make it pass. What it would catch is a
    # future arm that quietly started a session to keep an execution warm, which is
    # exactly the regression it is here for.
    test "with nothing holding it", %{execution_id: execution_id} do
      view = seen(execution_id)

      assert Registry.count(Statifier.Registry) == 0
      refute Enum.any?(Map.values(view), &is_pid/1)
    end

    # And it resumes in a process that has never seen it. The submit runs in
    # a task with its own everything; all it is given is the id.
    test "and resumes in a process that has never seen it", %{execution_id: execution_id} do
      owner = self()

      task =
        Task.async(fn ->
          Sandbox.allow(Repo, owner, self())

          Journey.submit(execution_id, "account_submitted", @account)
        end)

      assert {:ok, plan} = Task.await(task)
      assert key(plan) == "plan"

      # And the move is in storage, not in that task's memory.
      assert key(seen(execution_id)) == "plan"
    end
  end

  describe "a screen nobody answers" do
    # THE TIMEOUT CASE. The screen's deadline is a stored Oban job, armed by
    # `StatifierExamples.Charts.Timers` when the execution parked; draining the
    # queue is the day passing. What it takes is the await's `timed_out`
    # outcome, and the Path goes on to the next screen with nothing
    # captured - which is `StatifierExamples.Signup.Screen`'s "it abandons
    # the group, not the execution" in one execution.
    #
    # Sabotage: set the account screen's `timeout` param to "" in the Path
    # document. `core.await` writes no deadline send without one, the drain
    # found only the Path's own reminder, the execution stayed on the account
    # screen, and exactly this case went red. Reverted from a copy.
    test "times out, takes the timed_out slot, and the Path goes on", %{
      execution_id: execution_id
    } do
      assert key(seen(execution_id)) == "account"

      :ok = Phoenix.PubSub.subscribe(StatifierExamples.PubSub, Durable.topic(execution_id))

      # Two jobs are due: this screen's deadline and the Path's own reminder.
      assert %{success: 2, failure: 0} =
               Oban.drain_queue(queue: Timers.queue(), with_scheduled: true)

      assert key(seen(execution_id)) == "plan"

      # Nothing was captured, because a timeout captures nothing.
      assert seen(execution_id).responses == %{}

      assert timed_out?(execution_id)
    end

    # The deadline's own event, named by the compiler rather than by this
    # app: `core.await` emits `statifier_blocks.await.<block id>` and
    # transitions to its `timed_out` final on it. Asserted through the feed
    # the deadline's own drive produced, which is what a page watching the
    # execution would have drawn.
    defp timed_out?(execution_id) do
      assert_receive {:execution_advanced, ^execution_id, {%Durable{}, reading}}

      Enum.any?(reading.entries, fn entry ->
        entry.kind == :outcome and entry.detail == "timed_out on blk_sp_account_park"
      end) or timed_out?(execution_id)
    end
  end

  describe "a submit the screen refuses" do
    # Nothing is sent and nothing moves. The findings come back against the
    # same screen, and the execution's position in storage is untouched - which is
    # the property that matters: a refused submit is not a half-press.
    #
    # Sabotage: made `submit/3` press first and discard the findings. Two
    # cases went red, this one and the page's own refusal case: the execution moved
    # to the plan screen on a form holding one malformed address. Reverted
    # from a copy.
    test "sends nothing and leaves the run where it was", %{execution_id: execution_id} do
      assert {:invalid, view} =
               Journey.submit(execution_id, "account_submitted", %{"email" => "ada"})

      assert key(view) == "account"

      assert view.findings == [
               {"first_name", "is required"},
               {"email", "must look like an email address"}
             ]

      assert key(seen(execution_id)) == "account"
      assert seen(execution_id).responses == %{}
    end

    # Back is a button like any other, and that is the k2 finding happening:
    # `core.on_event` abandons the group, so the Path moves FORWARD. There is
    # no back edge here to give a reader, and there cannot be one until a
    # composite can declare an outcome per button (finding 1 of the spike
    # document).
    #
    # Sabotage: none available. The obvious one - making `submit/3` skip
    # validation for this button - is the field this bead removed for exactly
    # the reason it could not be sabotaged: the plan screen demands nothing,
    # so no press of Back can be refused, and a check that cannot fail cannot
    # be broken either. Recorded as an ask rather than shipped.
    test "Back abandons the screen and the Path goes on without a plan", %{
      execution_id: execution_id
    } do
      {:ok, _plan} = Journey.submit(execution_id, "account_submitted", @account)

      assert {:ok, moved} = Journey.submit(execution_id, "went_back", %{})

      # The branch on `responses.plan` takes neither arm, and the execution lands on
      # the confirm screen having gone nowhere near a plan.
      assert key(moved) == "confirm"
      refute Map.has_key?(moved.responses, "plan")

      # And the seat count the reader never typed is not written at all. A
      # capture pair whose source is absent from `_event.data` leaves its
      # destination UNWRITTEN as of `statifier_blocks` 0.28.0 (sb-ADR-0002's
      # capture Note, N2); before that release the destination was written
      # with the interpreter's `:undefined`, which is what finding 2 of the
      # k3 section recorded. Absence is the assertion, exactly as the `plan`
      # line two above it already reads.
      refute Map.has_key?(moved.responses, "seats")
    end
  end

  describe "a press the chart refused" do
    # The execution went terminal between the page being drawn and the button
    # being pressed - here by an explicit abandon, on a live wizard by the
    # abandonment deadline firing. Nothing the reader typed was wrong and
    # there is a real position to show, so this is neither `{:error, _}` nor
    # `{:invalid, _}`: it is the last settled position with the word for why
    # it did not move.
    #
    # `:failed` is the record's own status, which is the only reason
    # available - the driver's `{:discarded, run}` carries none - and it is
    # the same word `Durable.complete_invocation/3` reports for the same
    # reason.
    #
    # Sabotage: put `settle/3` back in `Durable.send_event/4`'s body, which
    # is the flattening this bead removed. This case went red on
    # `view.discarded` (the refused send came back `{:ok, _}` and the key was
    # never put), together with the driver's own case and the editor page's.
    # Reverted from a copy.
    test "answers the last settled position and says so", %{execution_id: execution_id} do
      assert {:ok, plan} = Journey.submit(execution_id, "account_submitted", @account)
      assert key(plan) == "plan"

      {:ok, {{durable, _run}, _document}} = Durable.resume(execution_id)
      assert :ok = Durable.abandon(durable)

      assert {:ok, view} = Journey.submit(execution_id, "personal_chosen", %{"seats" => "1"})

      assert view.discarded == :failed

      # The plan screen, not the confirm screen the press was reaching for,
      # and holding everything the chart had already collected.
      assert key(view) == "plan"
      assert view.status == :failed
      assert view.responses == @account
      refute Map.has_key?(view.responses, "plan")
    end

    # The key's absence is the information, so a press that DID move has to
    # be missing it. Without this a page could read `Map.get(view,
    # :discarded)` on every view and never notice the key had become
    # permanent.
    #
    # Sabotage: made `pressed/5` put `:discarded` on the drive arm too, with
    # `nil`. This case went red and nothing else did, which is the point of
    # having it. Reverted from a copy.
    test "and a press that moved carries no such key", %{execution_id: execution_id} do
      assert {:ok, plan} = Journey.submit(execution_id, "account_submitted", @account)

      refute Map.has_key?(plan, :discarded)
    end

    # se-ihi, counted rather than read, with the helper `current/1`'s own pin
    # uses. THE NUMBER IS THIS BEAD'S: there was no pin on `submit/3` before
    # it, and the count was NINE - `submit/3` resumed and then walked storage
    # again through `Durable.machine_state/1` for the datamodel, and
    # `pressed/5` walked it a third time after the send. Both walks returned
    # rows a driver in hand was already holding, and both are gone: the
    # resume's driver answers the pre-send datamodel and the send's driver
    # answers the moved one.
    #
    # What is left belongs to the two loads a press genuinely needs - the
    # resume before it and the drive itself - and pinning it is what keeps a
    # fourth walk from growing back unnoticed, which is exactly how the
    # first three arrived.
    #
    # Sabotage: restored `defp datamodel/1` and its call in `submit/3`. This
    # case went red at 7 reads and nothing else moved, which is the same
    # invisibility `current/1`'s pin was written for. Reverted from a copy.
    test "walks storage five times, not nine", %{execution_id: execution_id} do
      assert reads_during(fn ->
               assert {:ok, _plan} = Journey.submit(execution_id, "account_submitted", @account)
             end) == 5
    end
  end

  describe "a press the screen is not offering" do
    # A hidden button is not a button anyone pressed. Both plan buttons are
    # conditional on the seat count, so a press that arrives without one came
    # from a page drawn before it was typed.
    #
    # Sabotage: made `button/2` look through the screen's document nodes
    # instead of the resolved ones. Exactly this case went red: the execution
    # advanced on a button no reader could have seen, and the refusal it
    # asserts never came. Reverted from a copy.
    test "is refused rather than sent", %{execution_id: execution_id} do
      {:ok, _plan} = Journey.submit(execution_id, "account_submitted", @account)

      assert Journey.submit(execution_id, "business_chosen", %{"seats" => "1"}) ==
               {:error, {:unknown_outcome, "business_chosen"}}

      assert Journey.submit(execution_id, "not_an_outcome", %{}) ==
               {:error, {:unknown_outcome, "not_an_outcome"}}

      # The same press with the seat count that makes the button appear.
      assert {:ok, _mid_call} = Journey.submit(execution_id, "business_chosen", %{"seats" => "5"})
    end

    test "and so is a press against a run that is not on a screen", %{execution_id: execution_id} do
      {:ok, _plan} = Journey.submit(execution_id, "account_submitted", @account)
      {:ok, _mid_call} = Journey.submit(execution_id, "business_chosen", %{"seats" => "5"})

      assert Journey.submit(execution_id, "signup_confirmed", %{}) == {:error, :not_on_a_screen}
    end
  end

  describe "resolve/2, the draft half" do
    # What a page needs and a contract without it would get wrong: the plan
    # screen's buttons are conditional on a response given on that very
    # screen, so a resolve against the stored datamodel alone draws a screen
    # with no way off it.
    #
    # Sabotage: made `resolve/2` ignore its draft and answer the view
    # unchanged. Eight cases went red, this one on both button assertions and
    # the rest on the plan screen becoming a screen with no way off it - six
    # of them could not reach a plan at all. Reverted from a copy.
    test "a typed response changes what the screen offers", %{execution_id: execution_id} do
      {:ok, plan} = Journey.submit(execution_id, "account_submitted", @account)

      refute "plan_personal" in keys(plan)
      refute "plan_business" in keys(plan)

      assert "plan_personal" in keys(Journey.resolve(plan, %{"seats" => "1"}))
      assert "plan_business" in keys(Journey.resolve(plan, %{"seats" => "5"}))
    end

    test "a draft is never written to the run", %{execution_id: execution_id} do
      view = seen(execution_id)

      _drafted = Journey.resolve(view, %{"first_name" => "Ada"})

      assert seen(execution_id).responses == %{}
    end

    test "a view with no screen resolves to itself", %{execution_id: execution_id} do
      {:ok, _plan} = Journey.submit(execution_id, "account_submitted", @account)
      {:ok, mid_call} = Journey.submit(execution_id, "business_chosen", %{"seats" => "5"})

      assert Journey.resolve(mid_call, %{"anything" => "at all"}) == mid_call
    end
  end

  describe "payload/2, the host contract" do
    # The contract stated in code because neither document states it and
    # neither can check it (`docs/spikes/SF040-signup-skeleton.md`): what a
    # press sends is the form's responses, keyed by element key. Every
    # question's capture pair is a string source, so a press that omits a
    # typed answer writes nothing at that destination.
    #
    # There was a second half - a button's own declared literal map, merged
    # over the typed responses, the only way a press could once say anything
    # about itself. se-bzx (RQ-RF050-A3, 2026-09-18) dropped it. No button
    # this app ships had declared one since se-luu (RQ-RF046-4, 2026-09-13),
    # where the plan buttons started recording which of them fired through
    # the `["const", value]` capture form, out of the document; and this
    # module's own moduledoc argues elsewhere that a field no shipped screen
    # can exercise is a field no test can defend. So the case below is the
    # inverse of the one it replaces: a button held as data that DOES
    # declare such a map is ignored, and the press is the typed responses.
    #
    # Sabotage (2026-09-18): restored the merge in `payload/2` - the
    # `%{} = literals -> Map.merge(typed, literals)` arm it used to carry -
    # from a copy of `lib/statifier_examples/signup/journey.ex`. The first
    # assertion below went red, `%{"seats" => 1, "k" => "v"}` where
    # `%{"seats" => 1}` was expected, and no other case in this file moved,
    # because no shipped button declares such a map. Reverted from the copy.
    test "is the form's responses alone, and a button's own literals are ignored" do
      declared = %{"type" => "button", "key" => "x", "outcome" => "x", "payload" => %{"k" => "v"}}

      assert Journey.payload(declared, %{"seats" => 1}) == %{"seats" => 1}
      assert Journey.payload(Map.delete(declared, "payload"), %{"seats" => 5}) == %{"seats" => 5}
    end

    # se-luu: the fact the two end-to-end cases above rest on. No button this
    # app ships declares a `payload` map any more, so nothing the host sends
    # carries the plan - `responses.plan` is written out of the document.
    #
    # Sabotage: put `"payload": {"plan": "personal"}` back on `plan_personal`
    # in `priv/fixtures/signup_screens.json` from a copy; this case went red
    # and no other did, which is the point of it. Reverted from the copy.
    test "no shipped button declares a payload map" do
      for screen <- ["account", "plan", "confirm"],
          %{"type" => "button"} = button <- Screens.screen(screen).nodes do
        refute Map.has_key?(button, "payload")
      end
    end
  end
end
