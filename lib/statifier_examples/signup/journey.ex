defmodule StatifierExamples.Signup.Journey do
  @moduledoc """
  The signup Path as a **durable execution**: what a page shows, and what a press
  does to it.

  The three halves of the skeleton meet here.
  `StatifierExamples.Signup.Screens` (se-e68) says what is on a screen;
  `StatifierExamples.Signup.Screen` and `priv/fixtures/signup_path.json`
  (se-19h) say when a screen is reached and what a button's press means to
  the chart; this module is the loop between them, over
  `StatifierExamples.Charts.Durable`.

  ## Two functions, and that is the contract

  `current/1` **resolves**: an execution id in, the screen that execution is sitting on
  and the nodes to draw out. `submit/3` **presses**: an execution id, the outcome
  a button named, and what the form collected; findings back if the screen
  does not validate, and otherwise the next resolve.

  `resolve/2` is the first one again with a **draft**: the responses a reader
  has typed but not sent. A page needs it and a contract that omitted it
  would be wrong about this document, because an element's condition may
  read a response given on the screen it is on - the plan screen's two plan
  buttons are conditional on the seat count typed two lines above them, so
  a page resolving only against what the chart has stored would draw a
  screen with no way off it. The draft is never persisted and never sent;
  it is what the reader can see of their own typing.

  That pair is the shape Riddler R10e's presentation contract takes, and
  the two properties worth naming are what a host implementing it has to
  provide rather than what this app happens to do:

    * **Neither takes an execution.** Both take an execution *id* and load the execution from
      storage. There is no process to hand around, no session, and nothing
      in a socket that the next press depends on - which is what makes a
      journey survive a deploy, and what makes `submit/3` callable from a
      controller, a job, or a test just as well as from a LiveView.
    * **Neither returns a chart.** What comes back is a screen, some nodes,
      the responses so far and a status. A page built on this pair cannot
      reach into the execution, and so cannot start depending on the chart's
      shape.

  ## Where an execution rests, and how this finds out

  A `myapp.screen` expands to a group that presents the screen and then
  parks on a `core.await`, so **an execution waiting for a reader is an execution whose
  position includes that await's block** - `Screen.park_block_id/1` of the
  screen block's own id. `current/1` reads the reading's active blocks and
  looks for exactly that. An execution resting anywhere else is an execution with no
  screen to draw: mid-call on the asynchronous company-details step, or
  finished. Both answer `screen: nil`, and the page says so rather than
  guessing.

  ## The host contract is the form's responses, and nothing checks it

  A `capture` map's value whose shape is a **string** is a path inside
  `_event.data`, so what lands at `responses.<key>` for such a pair is
  whatever **the host** put in the event's data. This module is that host,
  so the contract is stated here in code:

      the press = the form's responses, keyed by element key

  That feeds every question's capture pair (destination `responses.<key>`,
  source `<key>`), and it is the whole of the contract this app leans on.
  Neither document states it and neither can check it;
  `docs/spikes/SF040-signup-skeleton.md` carries it as the ask.

  ## The button's own literal map, and why it is gone (2026-09-18, RQ-RF050-A3)

  There was a second half. The function now called `responses/1` merged the
  firing button's own declared literal map over the typed responses, which
  was how a press could say something about *itself*. The two plan buttons used it,
  declaring a literal plan value for a `writes` pair whose string source
  read it straight back out.

  Since 2026-09-13 (RQ-RF046-4) those buttons declare the literal capture
  form instead - `{"responses.plan": ["const", "business"]}` - which the
  compiled chart writes out of the **document**, so a press records which
  button fired without the host having to send anything for it.
  `StatifierExamples.Signup.Screen`'s moduledoc has the shape rule and the
  history.

  From that date no screen this app shipped could exercise the merge, and
  the section below makes exactly this argument about a different field: a
  field no shipped screen can exercise is a field no test can defend. So
  the merge is gone. A button that declares such a map is ignored, and what
  the press sends is the form's typed responses alone.

  ## Every button validates, and one of them should not

  `submit/3` runs the check over whichever button was pressed, Back
  included. That is wrong in general - a reader has to be able to leave a
  screen they have not finished - and it is unobservable in this Path,
  because the one screen with a second button asks for nothing required. An
  element document needs a way for a button to say it does not validate;
  this app had such a field for an afternoon and took it out again, because
  a field no shipped screen can exercise is a field no test can defend.
  `docs/spikes/SF040-signup-skeleton.md` carries it as the ask.

  ## Responses are coerced once, on the way in

  A form posts strings. A condition like `responses.seats > 1` - the confirm
  screen's referral question hangs off it - needs the number, and
  predicator will not compare a string to an integer. So a digits-only
  response is read as an integer **here**, before the chart is told anything,
  and the datamodel a resolve reads back is already typed. se-e68's page
  coerced in its render for want of a chart; this is the same two lines in
  the one place that now has somewhere to put them.
  """

  alias StatifierExamples.Charts
  alias StatifierExamples.Charts.{Durable, Execution}
  alias StatifierExamples.Signup.{Screen, Screens, Validation}

  @fixture "signup_path"

  @typedoc """
  What a page needs to draw one moment of an execution, and nothing else.

  `screen` is `nil` when the execution is not sitting on one (see the moduledoc),
  and `nodes` is then empty. `responses` is what the chart has collected so
  far, keyed by element key; `findings` is empty except in the
  `{:invalid, view}` a refused `submit/3` answers with.

  `discarded` is the one key that is not always there, and its absence is
  the information: a view carries it only when the press it answers was
  refused by the chart, and it holds the reason
  `StatifierExamples.Charts.Durable.send_event/4` gave. A page can
  therefore tell "this is where the execution is" from "this is where the
  execution is and your press did not move it" without comparing two
  readings.
  """
  @type view :: %{
          :execution_id => String.t(),
          :screen => Screens.screen() | nil,
          :nodes => [Screens.node_doc()],
          :datamodel => map(),
          :responses => %{optional(String.t()) => term()},
          :status => Execution.status(),
          :findings => [Validation.finding()],
          optional(:discarded) => term()
        }

  @doc """
  Starts a durable execution of the Path and drives it to its first screen.

  The execution id is the caller's to keep: it goes in the page's URL and it is
  the only handle anything here takes.
  """
  @spec start() :: {:ok, String.t()} | {:error, term()}
  def start, do: start(Durable.new_execution_id())

  @doc """
  `start/0` with the execution id supplied, which is what a test wants.
  """
  @spec start(String.t()) :: {:ok, String.t()} | {:error, term()}
  def start(execution_id) when is_binary(execution_id) do
    with {:ok, fixture} <- Charts.fixture(@fixture),
         {:ok, compiled} <-
           Durable.compile(fixture.document, fixture.declare, fixture.datamodel),
         {:ok, _driven} <- Durable.start(compiled, fixture.document, execution_id, fixture.key) do
      {:ok, execution_id}
    else
      :error -> {:error, :no_such_fixture}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  The resolve half: what the execution keyed `execution_id` is showing right now.

  Loads the execution cold - the position out of storage, the chart out of the
  record - so a caller that has only an id out of a URL is a caller in full
  possession of the execution.

  One load answers both halves of the view. The reading says where the
  execution is sitting and the datamodel says what it is holding, and both
  come out of the one `Durable.resume/1`: the position that resume loaded
  is on the driver it hands back, so the datamodel is read off it rather
  than fetched again through `Durable.machine_state/1`. Every page render
  paid for that second storage walk until se-w4i.

  `{:error, :execution_not_found}` for an id nobody stored, and the storage
  layer's own refusals otherwise.
  """
  @spec current(String.t()) :: {:ok, view()} | {:error, term()}
  def current(execution_id) when is_binary(execution_id) do
    with {:ok, {{%Durable{machine_state: state}, run}, _document}} <-
           Durable.resume(execution_id) do
      {:ok, view(execution_id, run, state.datamodel)}
    end
  end

  @doc """
  `view` re-resolved with `draft` - the responses a reader has typed on this
  screen and not sent - laid over what the chart has stored.

  The nodes and the responses move; nothing else does, and nothing is
  written. See the moduledoc on why a page cannot do without it.
  """
  @spec resolve(view(), %{optional(String.t()) => term()}) :: view()
  def resolve(%{screen: nil} = view, _draft), do: view

  def resolve(%{screen: screen, datamodel: datamodel} = view, draft) when is_map(draft) do
    merged = merged(datamodel, coerce(draft))

    %{view | responses: Map.fetch!(merged, "responses"), nodes: Screens.resolve(screen, merged)}
  end

  @doc """
  The submit half: validate what a screen collected, then raise the
  outcome `outcome`'s button named.

  `responses` is the form's, keyed by element key and holding strings.

  Three answers. `{:ok, view}` is the screen the execution moved to - or `nil`
  where it went somewhere with no screen. `{:invalid, view}` is the same
  screen again with `findings` filled in and **nothing sent**: a screen
  that does not validate never reaches the chart, so the execution's position
  does not move and neither does anything in storage. `{:error, reason}` is
  an execution that could not be loaded, or an outcome no button on the current
  screen declares.

  ## A press the chart refused is still `{:ok, view}`

  An execution that has gone terminal - abandoned, or finished elsewhere -
  between the page being drawn and the button being pressed takes no event.
  That is not an error and it is not an invalid screen: nothing about what
  the reader typed was wrong, and there is a real position to show. So the
  answer is `{:ok, view}` at the **last settled position**, carrying
  `discarded` with the reason. The position is the one the resume already
  loaded, because a refused send writes nothing and decodes nothing, so
  what the driver holds is still what storage holds.

  ## One load, not three

  The reading and the datamodel both come off the driver `Durable.resume/1`
  hands back, as `current/1` does. Until this drew them from there, `submit/3`
  paid for a `Durable.machine_state/1` walk before the send and `pressed/5`
  paid for a second one after it - four extra reads of the execution table
  on every press, all four returning rows the driver was already holding.

  The responses are merged into what the chart already holds before the
  screen is resolved for validation, because a question can be conditional
  on a response given on this very screen - the plan screen's business hint
  is - and validating against the position's stale datamodel would check
  the screen the reader saw one keystroke ago.
  """
  @spec submit(String.t(), String.t(), %{optional(String.t()) => term()}) ::
          {:ok, view()} | {:invalid, view()} | {:error, term()}
  def submit(execution_id, outcome, responses)
      when is_binary(execution_id) and is_binary(outcome) and is_map(responses) do
    with {:ok, {{%Durable{machine_state: state} = durable, run}, _document}} <-
           Durable.resume(execution_id),
         {:ok, drafted} <-
           parked_on(resolve(view(execution_id, run, state.datamodel), responses)),
         {:ok, button} <- button(drafted.nodes, outcome) do
      case Validation.validate(drafted.nodes, responses) do
        [] -> pressed(durable, run, execution_id, button, coerce(responses))
        findings -> {:invalid, %{drafted | findings: findings}}
      end
    end
  end

  @doc """
  What a press sends, for the responses `typed`: the responses.

  Public because it **is** the host contract the moduledoc describes, and a
  contract nothing can read is a contract nobody can check. The firing
  button is not an argument here and contributes nothing to what is sent.
  It could once name its own press through a literal map of its own; since
  2026-09-13 it says what it records through its `writes` pair instead, out
  of the document, and on 2026-09-18 the merge of that literal map over the
  typed responses stopped being read at all. `submit/3` is its only caller
  in `lib/`; `JourneyTest` calls it directly, which is what being public is
  for, and the spike document quotes it.

  Renamed 2026-09-18: this function used to be called payload and took the
  firing button as a first argument its body ignored. That name is a
  retired spelling, and since the literal-map arm was dropped it no longer
  said what the function answers.
  """
  @spec responses(%{optional(String.t()) => term()}) :: map()
  def responses(typed) when is_map(typed), do: typed

  # The press itself. `Screen.outcome_event/1` is the event the compiled
  # `core.on_event` for this button is listening for, and what it sends is
  # what that handler's `capture` map reads out of.
  #
  # Both the moved reading and the refused one come off a driver already in
  # hand: the one the send answers with on the drive arm, the one that was
  # passed in on the discard arm. A refused send neither decodes a position
  # nor writes one, so the driver `submit/3` resumed is still holding what
  # storage holds - which is what makes the last settled position free to
  # report rather than something to go and read again.
  @spec pressed(Durable.t(), Execution.t(), String.t(), Screens.node_doc(), map()) ::
          {:ok, view()} | {:error, term()}
  defp pressed(%Durable{machine_state: settled} = durable, run, execution_id, button, typed) do
    event = Screen.outcome_event(Map.fetch!(button, "outcome"))

    case Durable.send_event(durable, run, event, responses(typed)) do
      {:ok, {%Durable{machine_state: moved_state}, moved}} ->
        {:ok, view(execution_id, moved, moved_state.datamodel)}

      {:discarded, reason} ->
        {:ok, Map.put(view(execution_id, run, settled.datamodel), :discarded, reason)}

      {:error, _reason} = error ->
        error
    end
  end

  @spec view(String.t(), Execution.t(), map()) :: view()
  defp view(execution_id, run, datamodel) do
    screen = screen_at(run)
    responses = Map.get(datamodel, "responses") || %{}

    %{
      execution_id: execution_id,
      screen: screen,
      nodes: if(screen, do: Screens.resolve(screen, datamodel), else: []),
      datamodel: datamodel,
      responses: responses,
      status: run.status,
      findings: []
    }
  end

  # A view with a screen in it, as an error-shaped answer for `submit/3`:
  # pressing a button on an execution that has moved on is not a validation
  # failure, it is a stale page.
  @spec parked_on(view()) :: {:ok, view()} | {:error, :not_on_a_screen}
  defp parked_on(%{screen: nil}), do: {:error, :not_on_a_screen}
  defp parked_on(view), do: {:ok, view}

  # Which screen a position is resting in. The park block of each
  # `myapp.screen` the Path names, looked for in the reading's active
  # blocks; `nil` when the execution is resting anywhere else.
  @spec screen_at(Execution.t()) :: Screens.screen() | nil
  defp screen_at(%Execution{active: active}) do
    parks = MapSet.new(active)

    Enum.find_value(StatifierExamples.Signup.Path.screen_refs(document()), fn {id, key} ->
      MapSet.member?(parks, Screen.park_block_id(id)) && Screens.screen(key)
    end)
  end

  # The button among the nodes the reader can actually see. A button a
  # condition is hiding is not a button anyone pressed, so an outcome
  # naming one is `{:unknown_outcome, _}` rather than a press: the plan
  # screen's two plan buttons are conditional on the seat count, and a
  # press that arrived without one is a press from a page drawn before it
  # was typed.
  @spec button([Screens.node_doc()], String.t()) ::
          {:ok, Screens.node_doc()} | {:error, {:unknown_outcome, String.t()}}
  defp button(nodes, outcome) do
    case Enum.find(nodes, &(&1["type"] == "button" and &1["outcome"] == outcome)) do
      nil -> {:error, {:unknown_outcome, outcome}}
      button -> {:ok, button}
    end
  end

  @spec merged(map(), map()) :: map()
  defp merged(datamodel, typed) do
    Map.put(datamodel, "responses", Map.merge(Map.get(datamodel, "responses") || %{}, typed))
  end

  @spec document() :: StatifierBlocks.Document.t()
  defp document, do: StatifierExamples.Signup.Path.document()

  # See the moduledoc: a digits-only response becomes the integer a condition
  # can compare. Everything else travels as the string the form posted.
  @spec coerce(%{optional(String.t()) => term()}) :: map()
  defp coerce(responses) do
    Map.new(responses, fn
      {key, value} when is_binary(value) ->
        case Integer.parse(value) do
          {number, ""} -> {key, number}
          _not_an_integer -> {key, value}
        end

      {key, value} ->
        {key, value}
    end)
  end
end
