defmodule StatifierExamples.Signup.JourneyTest do
  @moduledoc """
  The Journey loop end to end: the Path as a durable run, three submits, a
  screen nobody answers, and the create-account call the run ends on.

  Not async: durable runs step through the application's named
  `StatifierExamples.Charts.RunLock`, and the timers are rows.

  ## The acceptance line, and where it could not be met literally

  `se-7wt` asks for "an end-to-end test [that] drives three submits and one
  timeout through the durable run". Three submits and one timeout cannot
  share a run here: the Path has three screens, a timed-out screen is by
  definition one that was **not** submitted, and a run that took all three
  buttons has finished before any deadline can elapse. So the end-to-end
  obligation is met by two runs in this module - "three submits" below, and
  "a screen nobody answers" beside it - and the divergence is recorded here
  rather than papered over by a test that drives both in one function and
  calls itself one run.
  """

  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias StatifierExamples.Charts.{AsyncCalls, Durable, Timers}
  alias StatifierExamples.Repo
  alias StatifierExamples.Signup.{Journey, Screens}

  @account %{"first_name" => "Ada", "email" => "ada@example.com"}

  setup do
    :ok = Sandbox.checkout(Repo)

    {:ok, run_id} = Journey.start("journey-#{System.unique_integer([:positive])}")

    %{run_id: run_id}
  end

  defp key(%{screen: nil}), do: nil
  defp key(%{screen: screen}), do: screen.key

  defp keys(%{nodes: nodes}), do: Enum.map(nodes, & &1["key"])

  # Everything a run's own reader can see of it, loaded the way a page
  # loads it: from the id and nothing else.
  defp seen(run_id) do
    {:ok, view} = Journey.current(run_id)

    view
  end

  describe "the run starts on the first screen" do
    test "and the screen is resolved against an empty datamodel", %{run_id: run_id} do
      view = seen(run_id)

      assert key(view) == "account"
      assert view.status == :running
      assert view.answers == %{}

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
    # case was not among them: a run that does not exist has no screen to
    # miss. Reverted from a copy.
    test "a run id nobody stored is a refusal, not an empty page" do
      assert Journey.current("no-such-run") == {:error, :run_not_found}
    end
  end

  describe "three submits" do
    # THE END-TO-END CASE. Three presses, each one a cold load from storage,
    # and what comes back at the end is the receipt the create-account call
    # answered with. The seat count decides the branch: one seat is the
    # personal arm, which this app answers synchronously.
    #
    # Sabotage: made `pressed/5` send the outcome event with no payload
    # (`Durable.send_event/4`'s default). Five cases went red, this one at
    # its first assertion about `answers`: every capture wrote `:undefined`,
    # so the branch on `answers.plan` took neither arm and three cases that
    # only wanted a run somewhere down the business arm fell over too.
    # Reverted from a copy.
    test "drive the run from the first screen to the created account", %{run_id: run_id} do
      assert {:ok, plan} = Journey.submit(run_id, "account_submitted", @account)
      assert key(plan) == "plan"
      assert plan.answers == %{"first_name" => "Ada", "email" => "ada@example.com"}

      assert {:ok, confirm} = Journey.submit(run_id, "personal_chosen", %{"seats" => "1"})
      assert key(confirm) == "confirm"
      assert confirm.answers["plan"] == "personal"

      # Coerced on the way in, which is what lets the confirm screen's
      # conditional half stay off for a one-seat signup.
      assert confirm.answers["seats"] == 1
      assert keys(confirm) == ["confirm_heading", "confirm_summary", "confirm_finish"]

      # The paragraph reads back the address the first screen collected,
      # through the chart rather than through the socket.
      assert Enum.find(confirm.nodes, &(&1["key"] == "confirm_summary"))["text"] =~
               "ada@example.com"

      assert {:ok, done} = Journey.submit(run_id, "signup_confirmed", %{})
      assert done.status == :done
      assert key(done) == nil

      # The stub create-account call, and the proof it was handed the
      # answers rather than a step name: it echoes the address back.
      assert done.datamodel["created"] == %{
               "created" => true,
               "email" => "ada@example.com",
               "collected" => 5
             }
    end

    # The other arm, and the shape se-d74 built: more than one seat is the
    # business plan, whose company-details step this app runs as an Oban job.
    # The run rests durably in the middle of the call - no screen, no
    # process, a live invocation - and the job's answer is what moves it on.
    #
    # Sabotage: made `payload/2` ignore the button's `payload` map. Five
    # cases went red, this one on the `screen: nil` rest: `answers.plan` came
    # back `:undefined`, the branch took neither arm, and no call was ever
    # made. Reverted from a copy.
    test "the business arm rests durably on an asynchronous call", %{run_id: run_id} do
      {:ok, _plan} = Journey.submit(run_id, "account_submitted", @account)

      assert {:ok, mid_call} = Journey.submit(run_id, "business_chosen", %{"seats" => "5"})
      assert key(mid_call) == nil
      assert mid_call.status == :running
      assert mid_call.answers["plan"] == "business"

      assert %{success: 1} = Oban.drain_queue(queue: AsyncCalls.queue())

      resumed = seen(run_id)
      assert key(resumed) == "confirm"

      # Five seats turns the confirm screen's conditional half on.
      assert "referral" in keys(resumed)

      assert {:ok, done} =
               Journey.submit(run_id, "signup_confirmed", %{"referral" => "A colleague"})

      assert done.status == :done
      assert done.datamodel["created"]["created"] == true
    end
  end

  describe "the run parks between screens" do
    # "No process alive" in the only sense that can be asserted: nothing in
    # this app holds a parked run. A `Statifier.Session` would be registered
    # under the engine's own registry (st-ADR-0027) and there is none, and
    # the view a page draws carries no pid of any kind.
    #
    # No sabotage: this case asserts an absence, so there is nothing in
    # `lib/` to break that would make it pass. What it would catch is a
    # future arm that quietly started a session to keep a run warm, which is
    # exactly the regression it is here for.
    test "with nothing holding it", %{run_id: run_id} do
      view = seen(run_id)

      assert Registry.count(Statifier.Registry) == 0
      refute Enum.any?(Map.values(view), &is_pid/1)
    end

    # And it resumes in a process that has never seen it. The submit runs in
    # a task with its own everything; all it is given is the id.
    test "and resumes in a process that has never seen it", %{run_id: run_id} do
      owner = self()

      task =
        Task.async(fn ->
          Sandbox.allow(Repo, owner, self())

          Journey.submit(run_id, "account_submitted", @account)
        end)

      assert {:ok, plan} = Task.await(task)
      assert key(plan) == "plan"

      # And the move is in storage, not in that task's memory.
      assert key(seen(run_id)) == "plan"
    end
  end

  describe "a screen nobody answers" do
    # THE TIMEOUT CASE. The screen's deadline is a stored Oban job, armed by
    # `StatifierExamples.Charts.Timers` when the run parked; draining the
    # queue is the day passing. What it takes is the await's `timed_out`
    # outcome, and the Path goes on to the next screen with nothing
    # captured - which is `StatifierExamples.Signup.Screen`'s "it abandons
    # the group, not the run" in one run.
    #
    # Sabotage: set the account screen's `timeout` param to "" in the Path
    # document. `core.await` writes no deadline send without one, the drain
    # found only the Path's own reminder, the run stayed on the account
    # screen, and exactly this case went red. Reverted from a copy.
    test "times out, takes the timed_out slot, and the Path goes on", %{run_id: run_id} do
      assert key(seen(run_id)) == "account"

      :ok = Phoenix.PubSub.subscribe(StatifierExamples.PubSub, Durable.topic(run_id))

      # Two jobs are due: this screen's deadline and the Path's own reminder.
      assert %{success: 2, failure: 0} =
               Oban.drain_queue(queue: Timers.queue(), with_scheduled: true)

      assert key(seen(run_id)) == "plan"

      # Nothing was captured, because a timeout captures nothing.
      assert seen(run_id).answers == %{}

      assert timed_out?(run_id)
    end

    # The deadline's own event, named by the compiler rather than by this
    # app: `core.await` emits `statifier_blocks.await.<block id>` and
    # transitions to its `timed_out` final on it. Asserted through the feed
    # the deadline's own drive produced, which is what a page watching the
    # run would have drawn.
    defp timed_out?(run_id) do
      assert_receive {:run_advanced, ^run_id, {%Durable{}, reading}}

      Enum.any?(reading.entries, fn entry ->
        entry.kind == :outcome and entry.detail == "timed_out on blk_sp_account_park"
      end) or timed_out?(run_id)
    end
  end

  describe "a submit the screen refuses" do
    # Nothing is sent and nothing moves. The findings come back against the
    # same screen, and the run's position in storage is untouched - which is
    # the property that matters: a refused submit is not a half-press.
    #
    # Sabotage: made `submit/3` press first and discard the findings. Two
    # cases went red, this one and the page's own refusal case: the run moved
    # to the plan screen on a form holding one malformed address. Reverted
    # from a copy.
    test "sends nothing and leaves the run where it was", %{run_id: run_id} do
      assert {:invalid, view} = Journey.submit(run_id, "account_submitted", %{"email" => "ada"})

      assert key(view) == "account"

      assert view.findings == [
               {"first_name", "is required"},
               {"email", "must look like an email address"}
             ]

      assert key(seen(run_id)) == "account"
      assert seen(run_id).answers == %{}
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
    test "Back abandons the screen and the Path goes on without a plan", %{run_id: run_id} do
      {:ok, _plan} = Journey.submit(run_id, "account_submitted", @account)

      assert {:ok, moved} = Journey.submit(run_id, "went_back", %{})

      # The branch on `answers.plan` takes neither arm, and the run lands on
      # the confirm screen having gone nowhere near a plan.
      assert key(moved) == "confirm"
      refute Map.has_key?(moved.answers, "plan")

      # And the seat count the reader never typed is written all the same, as
      # `:undefined`: a capture map's destination is written whether or not
      # the payload carries its source. Finding 2 of the k3 section.
      assert moved.answers["seats"] == :undefined
    end
  end

  describe "a press the screen is not offering" do
    # A hidden button is not a button anyone pressed. Both plan buttons are
    # conditional on the seat count, so a press that arrives without one came
    # from a page drawn before it was typed.
    #
    # Sabotage: made `button/2` look through the screen's document nodes
    # instead of the resolved ones. Exactly this case went red: the run
    # advanced on a button no reader could have seen, and the refusal it
    # asserts never came. Reverted from a copy.
    test "is refused rather than sent", %{run_id: run_id} do
      {:ok, _plan} = Journey.submit(run_id, "account_submitted", @account)

      assert Journey.submit(run_id, "business_chosen", %{"seats" => "1"}) ==
               {:error, {:unknown_outcome, "business_chosen"}}

      assert Journey.submit(run_id, "not_an_outcome", %{}) ==
               {:error, {:unknown_outcome, "not_an_outcome"}}

      # The same press with the seat count that makes the button appear.
      assert {:ok, _mid_call} = Journey.submit(run_id, "business_chosen", %{"seats" => "5"})
    end

    test "and so is a press against a run that is not on a screen", %{run_id: run_id} do
      {:ok, _plan} = Journey.submit(run_id, "account_submitted", @account)
      {:ok, _mid_call} = Journey.submit(run_id, "business_chosen", %{"seats" => "5"})

      assert Journey.submit(run_id, "signup_confirmed", %{}) == {:error, :not_on_a_screen}
    end
  end

  describe "resolve/2, the draft half" do
    # What a page needs and a contract without it would get wrong: the plan
    # screen's buttons are conditional on an answer given on that very
    # screen, so a resolve against the stored datamodel alone draws a screen
    # with no way off it.
    #
    # Sabotage: made `resolve/2` ignore its draft and answer the view
    # unchanged. Eight cases went red, this one on both button assertions and
    # the rest on the plan screen becoming a screen with no way off it - six
    # of them could not reach a plan at all. Reverted from a copy.
    test "a typed answer changes what the screen offers", %{run_id: run_id} do
      {:ok, plan} = Journey.submit(run_id, "account_submitted", @account)

      refute "plan_personal" in keys(plan)
      refute "plan_business" in keys(plan)

      assert "plan_personal" in keys(Journey.resolve(plan, %{"seats" => "1"}))
      assert "plan_business" in keys(Journey.resolve(plan, %{"seats" => "5"}))
    end

    test "a draft is never written to the run", %{run_id: run_id} do
      view = seen(run_id)

      _drafted = Journey.resolve(view, %{"first_name" => "Ada"})

      assert seen(run_id).answers == %{}
    end

    test "a view with no screen resolves to itself", %{run_id: run_id} do
      {:ok, _plan} = Journey.submit(run_id, "account_submitted", @account)
      {:ok, mid_call} = Journey.submit(run_id, "business_chosen", %{"seats" => "5"})

      assert Journey.resolve(mid_call, %{"anything" => "at all"}) == mid_call
    end
  end

  describe "payload/2, the host contract" do
    # The contract stated in code because neither document states it and
    # neither can check it (`docs/spikes/SF040-signup-skeleton.md`). A
    # button's `payload` is the only way a press says anything about itself:
    # a capture value is a path inside `_event.data`, never a literal, so
    # both plan buttons compile to the same assign.
    #
    # A pure case; the sabotage for the behaviour is on the business arm
    # above.
    test "is the form's answers plus the button's own literals" do
      [personal, business, back] =
        for %{"type" => "button"} = node <- Screens.screen("plan").nodes, do: node

      assert Journey.payload(personal, %{"seats" => 1}) == %{"seats" => 1, "plan" => "personal"}
      assert Journey.payload(business, %{"seats" => 5}) == %{"seats" => 5, "plan" => "business"}
      assert Journey.payload(back, %{"seats" => 5}) == %{"seats" => 5}
    end
  end
end
