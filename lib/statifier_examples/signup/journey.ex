defmodule StatifierExamples.Signup.Journey do
  @moduledoc """
  The signup Path as a **durable execution**: what a page shows, and what a press
  does to it.

  The three halves of the skeleton meet here.
  `StatifierExamples.Signup.Screens` says what is on a screen;
  `StatifierExamples.Signup.Screen` and `priv/fixtures/signup_path.json`
  say when a screen is reached and what a button's press means to
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

  That pair is the shape Riddler's presentation contract (ruled by the
  operator, 2026-09-12) takes, and
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

  ## What a page draws is riddler's answer

  The execution says where it is; `Riddler.Journey.present/3` says what that
  means to a reader. A view maps the execution onto riddler's status, and
  the execution's own status comes first: an execution that is no longer
  running is `:done` wherever it rests, a running one whose park block is
  active is `{:screen, key}`, and a running one resting anywhere else is
  `:waiting`. The view reads the nodes and the `state` off riddler's answer,
  with the datamodel as the root. So a view's `nodes` are riddler's resolved
  nodes, and its `state` is riddler's `"screen"`, `"waiting"` or `"done"`.

  A finished execution still parked on a screen - abandoned there, or
  failed - therefore answers `state: "done"` and **no nodes**, because
  riddler's done answer carries no screen: a reader is not handed inputs
  for a press the chart will discard. `screen` still names the screen it
  rests on, so a page can say where it stopped. `resolve/2` re-resolves
  that screen against a draft whatever the state, which is how `submit/3`
  still finds the pressed button and answers the refused press as
  `discarded`.

  ## A screens document the caller supplies

  What is on the Path's screens is `priv/fixtures/signup_screens.json`
  unless a caller passes `screens:` - a decoded screens document - to
  `start/2`, `current/2` and `submit/4`, and the execution never stores it:
  like the execution id, it is the caller's to keep and to pass on every
  call. `start/2` refuses a document riddler does not admit with zero
  findings, and one that leaves a screen the Path names undeclared. Its
  buttons have to declare the outcomes the Path's screens declare, because
  those are the events the chart listens for.

  ## A Path the caller supplies

  The chart is the Path fixture unless a caller passes `path:` - a block
  document - beside `screens:`, on every call, as it passes the screens.
  The execution never stores that either: `current/2` and `submit/4`
  compile the document they are handed and resume the execution on it, and
  a document that is not the one `start/2` was given is refused by the
  storage layer's identity guard. `start/2` refuses one that does not
  compile, as `{:error, {:path_document, findings}}`.

  A screen of a supplied Path is wherever it parks: a `myapp.screen`
  block's park, as the fixture's are, or a `core.await` listening for a
  screen's park event (`StatifierExamples.Signup.Screen.parked_screen/1`),
  which is how a Path built out of `core.*` blocks says the same thing.
  `StatifierExamples.ScreenEditor.Try` derives one of those from a screens
  document authored in the screen editor, whose screen keys and outcomes
  are its own.

  ## The host contract is the form's responses, and nothing checks it

  A `capture` map's value whose shape is a **string** is a path inside
  `_event.data`, so what lands at `responses.<key>` for such a pair is
  whatever **the host** put in the event's data. This module is that host,
  so the contract is stated here in code:

      the press = the form's responses, keyed by element key

  That feeds every question's capture pair (destination `responses.<key>`,
  source `<key>`), and it is the whole of the contract this app leans on.
  Neither document states it and neither can check it;
  `docs/spikes/signup-skeleton-spike.md` carries it as the ask.

  ## The button's own literal map, and why it is gone (ruled by the operator, 2026-09-18)

  There was a second half. The function now called `responses/1` merged the
  firing button's own declared literal map over the typed responses, which
  was how a press could say something about *itself*. The two plan buttons used it,
  declaring a literal plan value for a `writes` pair whose string source
  read it straight back out.

  Since 2026-09-13 (ruled by the operator) those buttons declare the literal
  capture form instead - `{"responses.plan": ["const", "business"]}` - which
  the compiled chart writes out of the **document**, so a press records which
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
  `docs/spikes/signup-skeleton-spike.md` carries it as the ask.

  ## Responses are coerced once, on the way in

  A form posts strings. A condition like `responses.seats > 1` - the confirm
  screen's referral question hangs off it - needs the number, and
  predicator will not compare a string to an integer. So a digits-only
  response is read as an integer **here**, before the chart is told anything,
  and the datamodel a resolve reads back is already typed. The screens page
  coerced in its render for want of a chart; this is the same two lines in
  the one place that now has somewhere to put them.
  """

  alias StatifierBlocks.{Block, Compiled, Document}
  alias StatifierExamples.Charts
  alias StatifierExamples.Charts.{Durable, Execution}
  alias StatifierExamples.Signup.{Screen, Screens, Validation}

  @fixture "signup_path"

  # A screens document as a call reads it: decoded, and admitted by riddler.
  @typep screens :: {map(), Riddler.Screens.Document.t()}

  @typedoc """
  What a page needs to draw one moment of an execution, and nothing else.

  `screen` is `nil` when the execution is not sitting on one (see the moduledoc),
  and `nodes` is then empty. `state` is `Riddler.Journey.present/3`'s
  `"screen"`, `"waiting"` or `"done"` for it; a view whose state is `"done"`
  has empty `nodes` even where `screen` names the screen the execution
  stopped on. `responses` is what the chart
  has collected so far, keyed by element key; `findings` is empty except in the
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
          :state => String.t(),
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
  def start(execution_id) when is_binary(execution_id), do: start(execution_id, [])

  @doc """
  `start/1` over the screens document `opts[:screens]` supplies, when it
  supplies one (see the moduledoc).

  `{:error, {:screens_document, reason}}` for a document riddler does not
  admit with zero findings - `reason` is `StatifierExamples.Signup.Screens.admit/1`'s
  - and `{:error, {:undeclared_screens, keys}}` for one that does not
  declare every screen the Path names. Nothing is started for either.
  """
  @spec start(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def start(execution_id, opts) when is_binary(execution_id) and is_list(opts) do
    with {:ok, screens} <- screens_document(opts),
         {:ok, {path, compiled, fixture_key}} <- path_chart(opts),
         :ok <- declares_path_screens(screens, path),
         {:ok, _driven} <- Durable.start(compiled, path, execution_id, fixture_key) do
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
  once paid for that second storage walk.

  `{:error, :execution_not_found}` for an id nobody stored, and the storage
  layer's own refusals otherwise.

  `opts[:screens]` and `opts[:path]` are the screens document and the Path
  `start/2` was given, when it was given them.
  """
  @spec current(String.t(), keyword()) :: {:ok, view()} | {:error, term()}
  def current(execution_id, opts \\ []) when is_binary(execution_id) and is_list(opts) do
    with {:ok, screens} <- screens_document(opts),
         {:ok, {{%Durable{machine_state: state}, run}, path}} <- resume(execution_id, opts) do
      {:ok, view(execution_id, run, state.datamodel, screens, path)}
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

  `opts[:screens]` and `opts[:path]` are the screens document and the Path
  `start/2` was given, when it was given them.
  """
  @spec submit(String.t(), String.t(), %{optional(String.t()) => term()}, keyword()) ::
          {:ok, view()} | {:invalid, view()} | {:error, term()}
  def submit(execution_id, outcome, responses, opts \\ [])
      when is_binary(execution_id) and is_binary(outcome) and is_map(responses) and
             is_list(opts) do
    with {:ok, screens} <- screens_document(opts),
         {:ok, {{%Durable{machine_state: state} = durable, run}, path}} <-
           resume(execution_id, opts),
         {:ok, drafted} <-
           parked_on(resolve(view(execution_id, run, state.datamodel, screens, path), responses)),
         {:ok, button} <- button(drafted.nodes, outcome) do
      case Validation.validate(drafted.nodes, responses) do
        [] -> pressed(durable, run, execution_id, button, coerce(responses), {screens, path})
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
  @spec pressed(
          Durable.t(),
          Execution.t(),
          String.t(),
          Screens.node_doc(),
          map(),
          {screens(), Document.t()}
        ) ::
          {:ok, view()} | {:error, term()}
  defp pressed(
         %Durable{machine_state: settled} = durable,
         run,
         execution_id,
         button,
         typed,
         {screens, path}
       ) do
    event = Screen.outcome_event(Map.fetch!(button, "outcome"))

    case Durable.send_event(durable, run, event, responses(typed)) do
      {:ok, {%Durable{machine_state: moved_state}, moved}} ->
        {:ok, view(execution_id, moved, moved_state.datamodel, screens, path)}

      {:discarded, reason} ->
        {:ok,
         Map.put(view(execution_id, run, settled.datamodel, screens, path), :discarded, reason)}

      {:error, _reason} = error ->
        error
    end
  end

  # The view for one reading. Where the execution is goes to
  # `Riddler.Journey.present/3` as its status, and what comes back is what
  # the view draws: the nodes off the answer's screen, and the answer's
  # state. `screen_at/2` only answers a key the document declares, so the
  # `{:screen, key}` status never meets `{:error, :no_such_screen}`.
  @spec view(String.t(), Execution.t(), map(), screens(), Document.t()) :: view()
  defp view(execution_id, run, datamodel, {document, admitted}, path) do
    key = screen_at(run, document, path)
    {:ok, answer} = Riddler.Journey.present(admitted, journey_status(key, run.status), datamodel)

    %{
      execution_id: execution_id,
      screen: key && Screens.screen(document, key),
      nodes: presented_nodes(answer),
      datamodel: datamodel,
      responses: Map.get(datamodel, "responses") || %{},
      status: run.status,
      state: Map.fetch!(answer, "state"),
      findings: []
    }
  end

  # The execution's position as `Riddler.Journey`'s status. Its own status
  # comes first: done once it has stopped running, wherever it rests. A
  # running execution is on a screen when one is parked, and waiting while
  # it runs on elsewhere - the moduledoc's mid-call.
  @spec journey_status(String.t() | nil, Execution.status()) :: Riddler.Journey.status()
  defp journey_status(_key, status) when status != :running, do: :done
  defp journey_status(key, :running) when is_binary(key), do: {:screen, key}
  defp journey_status(nil, :running), do: :waiting

  @spec presented_nodes(Riddler.Journey.answer()) :: [Screens.node_doc()]
  defp presented_nodes(%{"screen" => %{"nodes" => nodes}}), do: nodes
  defp presented_nodes(_no_screen), do: []

  # The screens document the call reads, decoded and admitted: the one
  # `opts[:screens]` supplies, or the fixture.
  @spec screens_document(keyword()) ::
          {:ok, screens()} | {:error, {:screens_document, term()}}
  defp screens_document(opts) do
    document = Keyword.get_lazy(opts, :screens, &Screens.document/0)

    case Screens.admit(document) do
      {:ok, admitted} -> {:ok, {document, admitted}}
      {:error, reason} -> {:error, {:screens_document, reason}}
    end
  end

  # The Path a call runs - the one `opts[:path]` supplies, or the fixture -
  # compiled, with the fixture key the execution records for it: none for a
  # supplied Path, which the caller passes on every call instead.
  @spec path_chart(keyword()) ::
          {:ok, {Document.t(), Compiled.t(), String.t() | nil}}
          | {:error, {:path_document, term()}}
          | :error
  defp path_chart(opts) do
    case Keyword.fetch(opts, :path) do
      {:ok, path} ->
        with {:ok, compiled} <- compile_path(path), do: {:ok, {path, compiled, nil}}

      :error ->
        with {:ok, fixture} <- Charts.fixture(@fixture),
             {:ok, compiled} <-
               Durable.compile(fixture.document, fixture.declare, fixture.datamodel) do
          {:ok, {fixture.document, compiled, fixture.key}}
        end
    end
  end

  @spec compile_path(Document.t()) ::
          {:ok, Compiled.t()} | {:error, {:path_document, term()}}
  defp compile_path(%Document{} = path) do
    case Durable.compile(path, []) do
      {:ok, compiled} -> {:ok, compiled}
      {:error, findings} -> {:error, {:path_document, findings}}
    end
  end

  # The execution and the Path it runs. A supplied Path is compiled and the
  # execution resumed on it; otherwise the chart comes out of the record, and
  # the Path read for its screens is the shipped one.
  @spec resume(String.t(), keyword()) ::
          {:ok, {{Durable.t(), Execution.t()}, Document.t()}} | {:error, term()}
  defp resume(execution_id, opts) do
    case Keyword.fetch(opts, :path) do
      {:ok, path} ->
        with {:ok, compiled} <- compile_path(path),
             {:ok, driven} <- Durable.resume(compiled, path, execution_id) do
          {:ok, {driven, path}}
        end

      :error ->
        with {:ok, {driven, _document}} <- Durable.resume(execution_id) do
          {:ok, {driven, document()}}
        end
    end
  end

  # Every screen the Path names has to be one the document declares, or the
  # execution would park on a screen with nothing to draw.
  @spec declares_path_screens(screens(), Document.t()) ::
          :ok | {:error, {:undeclared_screens, [String.t()]}}
  defp declares_path_screens({document, _admitted}, path) do
    undeclared =
      for {_park, key} <- parks(path),
          is_nil(Screens.screen(document, key)),
          uniq: true,
          do: key

    case undeclared do
      [] -> :ok
      keys -> {:error, {:undeclared_screens, keys}}
    end
  end

  # A view with a screen in it, as an error-shaped answer for `submit/3`:
  # pressing a button on an execution that has moved on is not a validation
  # failure, it is a stale page.
  @spec parked_on(view()) :: {:ok, view()} | {:error, :not_on_a_screen}
  defp parked_on(%{screen: nil}), do: {:error, :not_on_a_screen}
  defp parked_on(view), do: {:ok, view}

  # Which screen a position is resting in. The park of each screen the Path
  # names, looked for in the reading's active blocks; `nil` when the
  # execution is resting anywhere else, or on a screen `screens` does not
  # declare.
  @spec screen_at(Execution.t(), map(), Document.t()) :: String.t() | nil
  defp screen_at(%Execution{active: active}, screens, path) do
    active = MapSet.new(active)

    Enum.find_value(parks(path), fn {park, key} ->
      MapSet.member?(active, park) && Screens.screen(screens, key) && key
    end)
  end

  # Every park in a Path, in document order, with the screen key it is the
  # park of: a `myapp.screen` block's (`Screen.park_block_id/1` of its id),
  # and a `core.await` listening for a screen's park event (the moduledoc's
  # "A Path the caller supplies").
  @spec parks(Document.t()) :: [{String.t(), String.t()}]
  defp parks(%Document{} = path) do
    Enum.flat_map(Document.blocks(path), &park/1)
  end

  @spec park(Block.t()) :: [{String.t(), String.t()}]
  defp park(%Block{type: "myapp.screen", id: id, config: config}),
    do: [{Screen.park_block_id(id), Map.get(config, "screen", "")}]

  defp park(%Block{type: "core.await", id: id, config: %{"event" => event}})
       when is_binary(event) do
    case Screen.parked_screen(event) do
      nil -> []
      key -> [{id, key}]
    end
  end

  defp park(_block), do: []

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

  @spec document() :: Document.t()
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
