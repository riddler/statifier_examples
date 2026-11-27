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
  the execution's own status comes first:

    * an execution that is no longer running is `{:done, result}` wherever
      it rests, and `result` is what it finished with: the receipt the
      create-account call at the end of the Path wrote at `created`, under
      that key, or an empty map for an execution that stopped before the
      call answered;
    * a running one whose park block is active is `{:screen, key}`;
    * a running one resting anywhere else is `{:waiting, info}`: `info`'s
      `"reason"` names the step it waits on, `"company_details_pending"`
      for the business arm's asynchronous call (`"between_screens"` where
      no step of this app's is active), and its `"retry_after_ms"` says
      when to ask again.

  The view reads the nodes, the `state`, the waiting `reason` and
  `retry_after_ms` and the done `result` off riddler's answer, with the
  datamodel as the root. So a view's `nodes` are riddler's resolved nodes,
  and its `state` is riddler's `"screen"`, `"waiting"` or `"done"`.

  A finished execution still parked on a screen - abandoned there, or
  failed - therefore answers `state: "done"` and **no nodes**, because
  riddler's done answer carries no screen: a reader is not handed inputs
  for a press the chart will discard. `screen` still names the screen it
  rests on, so a page can say where it stopped. `resolve/2` is the one
  exception: it re-resolves that screen against a draft whatever the
  state, which is how `submit/3` still finds the pressed button and
  answers the refused press as `discarded`.

  A running execution parked on a screen the supplied screens document does
  not declare is neither: it is a caller passing `current/2` or `submit/4`
  a different document than it gave `start/2`, and both answer
  `{:error, {:undeclared_screen, key}}` naming the screen rather than
  presenting it as waiting.

  ## A screens document the caller supplies

  What is on the Path's screens is `priv/fixtures/signup_screens.json`
  unless a caller passes `screens:` - a decoded screens document - to
  `start/2`, `current/2` and `submit/4`, and the execution never stores it:
  like the execution id, it is the caller's to keep and to pass on every
  call. `start/2` refuses a document riddler does not admit with zero
  findings, and one that leaves a screen the Path names undeclared. Its
  buttons have to declare the outcomes the Path's screens declare, because
  those are the events the chart listens for.

  A `myapp.step` names its screen's buttons and questions in its own
  config (`StatifierExamples.Signup.ReturnableStep`), so `start/2` also
  refuses a Path with a step that disagrees with the screen it names: a
  button outcome or a response key the step configures and the screen does
  not carry, or a button or a question on the screen the step does not
  configure. The first is a press the reader can never make or an answer
  never asked; the second a press the chart has no transition for or an
  answer it never records.

  ## A Path the caller supplies

  The chart is the Path fixture unless a caller passes `path:` - a block
  document - beside `screens:`, on every call, as it passes the screens.
  The execution never stores that either: `current/2` and `submit/4`
  compile the document they are handed and resume the execution on it, and
  a document that is not the one `start/2` was given is refused by the
  storage layer's identity guard. `start/2` refuses one that does not
  compile, as `{:error, {:path_document, findings}}`.

  ## A durable subchart child

  A supplied Path may be running as a durable subchart child of another
  execution: a setup the branch onboarding started
  (`StatifierExamples.Library.Onboarding`). The driver created that
  execution with the child recipe,
  `StatifierExamples.Charts.Subchart.child_compile/1`, so its stored
  identity is that compile's. `current/2`, `submit/4` and `back/3` take
  `child: true` beside `path:` and `screens:` for such an execution and
  resume it on the child compile; without it the storage layer's identity
  guard refuses the resume. `start/2` does not read it: a child is started
  by the driver, never here.

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

  ## A secret question is sealed before the chart sees it

  A screen may ask a `secret_question` - the patron registration screens
  ask a new patron for the PIN of their library card. What the reader
  typed is validated as typed, and then, before anything is sent,
  `Riddler.Screens.seal_secrets/4` turns every secret question's response on
  the screen into the sealed form `%{"sealed" => string}`, with
  `StatifierExamples.Signup.Sealer.seal/1` as the sealer. Only the sealed
  responses reach the chart, so the event, the datamodel and every stored
  row hold the sealed string and never the text, and riddler presents the
  question as `held` from then on.

  The order is the point: the check reads the text, because a required
  PIN left blank is the reader's mistake to be told about, and the seal
  comes before the coercion below, because a PIN of digits alone is text
  and not a number. A response riddler will not seal, or a sealer that
  does not answer a sealed string, refuses the press as
  `{:error, {:seal_secrets, reason}}` and sends nothing. `resolve/2` never
  lays a secret question's typed response over the datamodel, so a view
  carries nothing of it either.

  ## Back through a returnable step

  A Path whose screens are `myapp.step` blocks
  (`StatifierExamples.Signup.ReturnableStep`) parks on the step's own
  block, and every such step is a returnable step, so the compiled chart
  keeps a trail of the steps it entered and answers `statifier_blocks`'
  reserved back event over it. Two things follow here.

  A view says whether Back is offered. `StatifierBlocks.Runtime.Back.offered?/3`
  answers it from the execution's datamodel, its active leaf states and the
  Path, and the answer goes to riddler as the screen status's `"back"`, so
  the view's `back` is riddler's moves' own. It is `false` at the first
  step, where there is nothing behind the reader, and everywhere in a Path
  with no returnable step - the signup Path's included, whose back edge on
  the plan screen is a button it authored.

  `back/3` goes back. It takes the request a client sends, decodes it with
  `Riddler.Journey.decode_submit/1`, and raises the reserved event on the
  execution; the execution re-enters the step before, whose screen is drawn
  with what the chart already holds for it. Nothing the reader typed on the
  screen they left is sent, so it is dropped, and the responses the chart
  held stay as they were.

  ## Responses are coerced once, on the way in

  A form posts strings. A condition like `responses.seats > 1` - the confirm
  screen's referral question hangs off it - needs the number, and
  predicator will not compare a string to an integer. So a digits-only
  response is read as an integer **here**, before the chart is told anything,
  and the datamodel a resolve reads back is already typed. The screens page
  coerced in its render for want of a chart; this is the same two lines in
  the one place that now has somewhere to put them.
  """

  alias Riddler.Journey.Scope
  alias Statifier.MachineState
  alias StatifierBlocks.{Block, Compiled, Document}
  alias StatifierBlocks.Runtime.Back
  alias StatifierExamples.Charts
  alias StatifierExamples.Charts.{Durable, Execution, Subchart}
  alias StatifierExamples.Signup.{ReturnableStep, Screen, Screens, Sealer, Validation}

  @fixture "signup_path"

  # The retry hint a waiting view carries (the moduledoc's "What a page
  # draws is riddler's answer").
  @retry_after_ms 5_000

  # A screens document as a call reads it: decoded, and admitted by riddler.
  @typep screens :: {map(), Riddler.Screens.Document.t()}

  @typedoc """
  What a page needs to draw one moment of an execution, and nothing else.

  `screen` is `nil` when the execution is not sitting on one (see the moduledoc),
  and `nodes` is then empty. `state` is `Riddler.Journey.present/3`'s
  `"screen"`, `"waiting"` or `"done"` for it; a view whose state is `"done"`
  has empty `nodes` even where `screen` names the screen the execution
  stopped on, except a view `resolve/2` answers, which fills that screen's
  nodes back in against the draft (the moduledoc's "What a page draws is
  riddler's answer"). `reason` and `retry_after_ms` are riddler's waiting
  answer's, and `nil` on any other state; `result` is riddler's done
  answer's, and `nil` on any other state: a done view always carries a
  map there, the create-account receipt under `"created"` or an empty
  map for an execution that stopped before it, never `nil`. `answer` is
  riddler's answer itself, the one the view was drawn from, for a page
  that draws it whole. `back` is riddler's moves'
  `"back"` on a `"screen"` view - whether going back from the screen
  would take the execution anywhere - and `false` on any other state.
  `responses` is what the chart
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
          :answer => Riddler.Journey.answer(),
          :screen => Screens.screen() | nil,
          :nodes => [Screens.node_doc()],
          :datamodel => map(),
          :responses => %{optional(String.t()) => term()},
          :status => Execution.status(),
          :state => String.t(),
          :back => boolean(),
          :reason => String.t() | nil,
          :retry_after_ms => non_neg_integer() | nil,
          :result => map() | nil,
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
  - `{:error, {:undeclared_screens, keys}}` for one that does not
  declare every screen the Path names, and
  `{:error, {:steps_disagree, disagreements}}` for a Path whose
  `myapp.step` blocks disagree with the screens they name (the
  moduledoc's "A screens document the caller supplies"). Each
  disagreement is `{block_id, reason, name}`, `reason` one of
  `:button_not_on_screen`, `:button_not_configured`,
  `:question_not_on_screen` and `:question_not_configured`, in document
  order. Nothing is started for any of them.

  `opts[:scope]`, a `Riddler.Journey.Scope`, is the scope the Journey is
  started under: the execution records it, and every durable subchart child
  it starts copies it (`StatifierExamples.Charts.Durable.scope/1`). An
  execution started without one records none. Only `start/2` reads it.
  """
  @spec start(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def start(execution_id, opts) when is_binary(execution_id) and is_list(opts) do
    scope = scope_data(Keyword.get(opts, :scope))

    with {:ok, screens} <- screens_document(opts),
         {:ok, {path, compiled, fixture_key}} <- path_chart(opts),
         :ok <- declares_path_screens(screens, path),
         :ok <- steps_agree(screens, path),
         {:ok, _driven} <- Durable.start(compiled, path, execution_id, fixture_key, scope) do
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

  `{:error, :execution_not_found}` for an id nobody stored,
  `{:error, {:undeclared_screen, key}}` for a running execution parked on a
  screen the screens document does not declare, and the storage layer's own
  refusals otherwise.

  `opts[:screens]` and `opts[:path]` are the screens document and the Path
  `start/2` was given, when it was given them.
  """
  @spec current(String.t(), keyword()) :: {:ok, view()} | {:error, term()}
  def current(execution_id, opts \\ []) when is_binary(execution_id) and is_list(opts) do
    with {:ok, screens} <- screens_document(opts),
         {:ok, {{%Durable{machine_state: state}, run}, path}} <- resume(execution_id, opts) do
      view(execution_id, run, state, screens, path)
    end
  end

  @doc """
  `view` re-resolved with `draft` - the responses a reader has typed on this
  screen and not sent - laid over what the chart has stored.

  The nodes and the responses move; nothing else does, and nothing is
  written. See the moduledoc on why a page cannot do without it. A secret
  question's response in the draft is left out: a view never holds the
  text a reader typed into one.
  """
  @spec resolve(view(), %{optional(String.t()) => term()}) :: view()
  def resolve(%{screen: nil} = view, _draft), do: view

  def resolve(%{screen: screen} = view, draft) when is_map(draft) do
    merged = drafted(view, draft)

    %{view | responses: Map.fetch!(merged, "responses"), nodes: Screens.resolve(screen, merged)}
  end

  @doc """
  The screen the execution keyed `execution_id` is parked on, presented
  again with `draft` - the responses a reader has typed on it and not
  sent - laid over what the chart has stored: riddler's answer, as
  `Riddler.Journey.present/3` gives it.

  It is `resolve/2` for a renderer that draws riddler's answer rather than
  a view: the draft is laid over the datamodel the same way, a secret
  question's response left out, and the screen is presented whatever the
  execution's state, as `resolve/2` re-resolves it, so a button the draft
  reveals is drawn on a page that has not yet learned the execution
  stopped, and the press is answered as `discarded` by `submit/4`. Nothing
  is sent and nothing is written. The answer goes through the same
  presented answer check as every answer a view is drawn from (the
  moduledoc's "What a page draws is riddler's answer").

  `{:error, :not_on_a_screen}` for an execution resting on no screen, and
  the refusals `current/2` answers.

  `opts[:screens]` and `opts[:path]` are the screens document and the Path
  `start/2` was given, when it was given them.
  """
  @spec present_draft(String.t(), %{optional(String.t()) => term()}, keyword()) ::
          {:ok, Riddler.Journey.answer()} | {:error, term()}
  def present_draft(execution_id, draft, opts \\ [])
      when is_binary(execution_id) and is_map(draft) and is_list(opts) do
    with {:ok, {_document, admitted} = screens} <- screens_document(opts),
         {:ok, {{%Durable{machine_state: state}, run}, path}} <- resume(execution_id, opts),
         {:ok, settled} <- view(execution_id, run, state, screens, path),
         {:ok, %{screen: %{key: key}} = on} <- parked_on(settled) do
      status = {:screen, key, %{"back" => on.back}}
      {:ok, answer} = Riddler.Journey.present(admitted, status, drafted(on, draft))
      :ok = check_presented(answer)

      {:ok, answer}
    end
  end

  # The datamodel with `draft` laid over its responses: coerced, and with
  # every secret question's response on the view's screen left out.
  @spec drafted(view(), %{optional(String.t()) => term()}) :: map()
  defp drafted(%{screen: screen, datamodel: datamodel}, draft) do
    merged(datamodel, draft |> coerce() |> Map.drop(secret_keys(screen.nodes)))
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
  an execution that could not be loaded, `{:undeclared_screen, key}` for a
  running execution parked on a screen the screens document does not
  declare, an outcome no button on the current
  screen declares, or `{:seal_secrets, reason}` for a secret question's
  response the screen could not seal (the moduledoc's "A secret question is
  sealed before the chart sees it"); nothing is sent for any of them.

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
         {:ok, settled} <- view(execution_id, run, state, screens, path),
         {:ok, drafted} <- parked_on(resolve(settled, responses)),
         {:ok, button} <- button(drafted.nodes, outcome),
         {:ok, sealed} <- checked(drafted, responses, screens) do
      pressed(durable, run, execution_id, button, coerce(sealed), {screens, path})
    end
  end

  # The press's responses checked as the reader typed them and then sealed
  # (the moduledoc's "A secret question is sealed before the chart sees
  # it"), or the drafted view with its findings when the check refuses them.
  @spec checked(view(), map(), screens()) ::
          {:ok, map()} | {:invalid, view()} | {:error, {:seal_secrets, term()}}
  defp checked(drafted, responses, screens) do
    case Validation.validate(drafted.nodes, responses) do
      [] -> seal(screens, drafted.screen, responses)
      findings -> {:invalid, %{drafted | findings: findings}}
    end
  end

  @doc """
  The back half: take the execution keyed `execution_id` back to the step
  it entered before the one it is on (the moduledoc's "Back through a
  returnable step").

  `request` is what the client sent, and it has to be riddler's back
  request, `%{"screen" => key, "back" => true}`: it is decoded with
  `Riddler.Journey.decode_submit/1`, and the screen it names has to be the
  one the execution is on.

  `{:ok, view}` is the screen the execution went back to, or, for an
  execution that stopped after it was loaded here and before the event
  reached it, the last settled position carrying `discarded`, as
  `submit/4` answers a refused press. An execution already stopped when it
  is loaded is refused: it offers no Back. Nothing is sent for any of the
  refusals:
  `{:error, {:back_request, findings}}` for a request riddler does not
  decode, `{:error, :not_a_back_request}` for one it decodes as a submit,
  `{:error, :not_on_a_screen}` for an execution resting on no screen,
  `{:error, {:stale_screen, key}}` when the execution is on a screen other
  than the one the request names, `{:error, :back_not_offered}` where the
  view's `back` is `false`, and the refusals `current/2` answers.

  `opts[:screens]` and `opts[:path]` are the screens document and the Path
  `start/2` was given, when it was given them.
  """
  @spec back(String.t(), map(), keyword()) :: {:ok, view()} | {:error, term()}
  def back(execution_id, request, opts \\ [])
      when is_binary(execution_id) and is_map(request) and is_list(opts) do
    with {:ok, key} <- back_request(request),
         {:ok, screens} <- screens_document(opts),
         {:ok, {{%Durable{machine_state: state} = durable, run}, path}} <-
           resume(execution_id, opts),
         {:ok, settled} <- view(execution_id, run, state, screens, path),
         {:ok, _on} <- parked_on(settled),
         :ok <- on_screen(settled, key),
         :ok <- back_offered(settled) do
      went_back(durable, run, execution_id, {screens, path})
    end
  end

  # The screen a back request names, once riddler has decoded it as one.
  @spec back_request(map()) ::
          {:ok, String.t()}
          | {:error, {:back_request, [Riddler.Finding.t()]} | :not_a_back_request}
  defp back_request(request) do
    case Riddler.Journey.decode_submit(request) do
      {:ok, %{"back" => true, "screen" => key}} -> {:ok, key}
      {:ok, _submit} -> {:error, :not_a_back_request}
      {:error, findings} -> {:error, {:back_request, findings}}
    end
  end

  @spec on_screen(view(), String.t()) :: :ok | {:error, {:stale_screen, String.t()}}
  defp on_screen(%{screen: %{key: key}}, key), do: :ok
  defp on_screen(%{screen: %{key: current}}, _key), do: {:error, {:stale_screen, current}}

  @spec back_offered(view()) :: :ok | {:error, :back_not_offered}
  defp back_offered(%{back: true}), do: :ok
  defp back_offered(_view), do: {:error, :back_not_offered}

  # The reserved back event, raised with no data: going back presses no
  # button, so nothing the reader typed travels with it.
  @spec went_back(Durable.t(), Execution.t(), String.t(), {screens(), Document.t()}) ::
          {:ok, view()} | {:error, term()}
  defp went_back(%Durable{machine_state: settled} = durable, run, execution_id, {screens, path}) do
    case Durable.send_event(durable, run, back_event()) do
      {:ok, {%Durable{machine_state: moved_state}, moved}} ->
        view(execution_id, moved, moved_state, screens, path)

      {:discarded, reason} ->
        with {:ok, view} <- view(execution_id, run, settled, screens, path) do
          {:ok, Map.put(view, :discarded, reason)}
        end

      {:error, _reason} = error ->
        error
    end
  end

  @doc """
  The reserved event that takes an execution back to the returnable step
  before its position: `statifier_blocks.back`, `statifier_blocks`'
  ADR-0004 Amendment of 2026-11-20, `L3`. The package spells it in its
  compiler and exports no function for it, so the host spells it here,
  once.
  """
  @spec back_event() :: String.t()
  def back_event, do: "statifier_blocks.back"

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
        view(execution_id, moved, moved_state, screens, path)

      {:discarded, reason} ->
        with {:ok, view} <- view(execution_id, run, settled, screens, path) do
          {:ok, Map.put(view, :discarded, reason)}
        end

      {:error, _reason} = error ->
        error
    end
  end

  # The view for one reading. Where the execution is goes to
  # `Riddler.Journey.present/3` as its status, and what comes back is what
  # the view draws: the nodes off the answer's screen, the answer's state,
  # its waiting reason and retry hint, and its done result. `screen_at/3`
  # only answers a key the document declares, so the `{:screen, key}`
  # status never meets `{:error, :no_such_screen}`.
  @spec view(String.t(), Execution.t(), MachineState.t(), screens(), Document.t()) ::
          {:ok, view()} | {:error, {:undeclared_screen, String.t()}}
  defp view(execution_id, run, %MachineState{datamodel: datamodel} = state, screens, path) do
    {document, admitted} = screens

    with {:ok, key} <- screen_at(run, document, path) do
      status = journey_status(key, run, path, state)
      {:ok, answer} = Riddler.Journey.present(admitted, status, datamodel)
      :ok = check_presented(answer)

      {:ok,
       %{
         execution_id: execution_id,
         answer: answer,
         screen: key && Screens.screen(document, key),
         nodes: presented_nodes(answer),
         datamodel: datamodel,
         responses: Map.get(datamodel, "responses") || %{},
         status: run.status,
         state: Map.fetch!(answer, "state"),
         back: back_presented?(answer),
         reason: Map.get(answer, "reason"),
         retry_after_ms: Map.get(answer, "retry_after_ms"),
         result: Map.get(answer, "result"),
         findings: []
       }}
    end
  end

  # The execution's position as `Riddler.Journey`'s status (the moduledoc's
  # "What a page draws is riddler's answer"). Its own status comes first:
  # done once it has stopped running, wherever it rests, with what it
  # finished with. A running execution is on a screen when one is parked,
  # and waiting while it runs on elsewhere - the moduledoc's mid-call.
  #
  # A screen is presented with `"back"` set to what statifier_blocks' Back
  # reader answers for the execution's position (the moduledoc's "Back
  # through a returnable step"), so riddler's moves say whether a Back
  # control belongs on it.
  @spec journey_status(String.t() | nil, Execution.t(), Document.t(), MachineState.t()) ::
          Riddler.Journey.status()
  defp journey_status(_key, %Execution{status: status}, _path, %MachineState{datamodel: datamodel})
       when status != :running,
       do: {:done, result(datamodel)}

  defp journey_status(key, %Execution{status: :running}, path, state) when is_binary(key),
    do: {:screen, key, %{"back" => back_offered?(state, path)}}

  defp journey_status(nil, %Execution{status: :running} = run, path, _state),
    do: {:waiting, waiting_info(run, path)}

  # statifier_blocks' Back reader over the execution's datamodel and its
  # active leaf states. A Path with no returnable step answers `false`
  # wherever it rests.
  @spec back_offered?(MachineState.t(), Document.t()) :: boolean()
  defp back_offered?(%MachineState{datamodel: datamodel} = state, path),
    do: Back.offered?(datamodel, Statifier.active_leaf_states(state), path)

  # Riddler's moves say whether Back is offered on the screen it presents;
  # every other answer carries no moves, and offers none.
  @spec back_presented?(Riddler.Journey.answer()) :: boolean()
  defp back_presented?(%{"moves" => %{"back" => back}}), do: back == true
  defp back_presented?(_no_moves), do: false

  # What a done execution finished with: the create-account call's receipt
  # under the key the Path writes it at, or nothing when the execution
  # stopped before that call answered.
  @spec result(map()) :: map()
  defp result(%{"created" => created}) when is_map(created), do: %{"created" => created}
  defp result(_datamodel), do: %{}

  # Why a running execution with no screen waits, and when to ask again.
  # The reason names the `myapp.signup_step` it is mid-call on; the retry
  # hint is the same for every step, because a page that subscribes redraws
  # when the call answers anyway, and a caller that polls instead needs
  # only a pace.
  @spec waiting_info(Execution.t(), Document.t()) :: Riddler.Journey.waiting_info()
  defp waiting_info(%Execution{active: active}, path) do
    active = MapSet.new(active)

    reason =
      Enum.find_value(Document.blocks(path), "between_screens", fn
        %Block{type: "myapp.signup_step", id: id, config: %{"step" => step}}
        when is_binary(step) ->
          MapSet.member?(active, id) && step <> "_pending"

        _block ->
          nil
      end)

    %{"reason" => reason, "retry_after_ms" => @retry_after_ms}
  end

  # The suite's check on riddler's answer. Under `config/test.exs` this
  # module's application environment names a module as
  # `:presented_answer_check`, whose `check!/1` raises for an answer that
  # does not keep to the presented answer schema riddler ships, so every
  # answer a Journey test or a page test draws from is checked before it is
  # drawn. Nothing names one outside the tests, and the answer is drawn as
  # riddler gives it.
  #
  # Only `Riddler.Journey.present/3` answers are checked: every view's, and
  # the one `present_draft/3` answers for a draft, which is what the Journey
  # page draws as a reader types. The nodes `resolve/2` answers are
  # resolved nodes, not a presented answer, and are not checked.
  @spec check_presented(Riddler.Journey.answer()) :: :ok
  defp check_presented(answer) do
    :statifier_examples
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:presented_answer_check)
    |> check_with(answer)
  end

  @spec check_with(module() | nil, Riddler.Journey.answer()) :: :ok
  defp check_with(nil, _answer), do: :ok
  defp check_with(check, answer), do: check.check!(answer)

  @spec presented_nodes(Riddler.Journey.answer()) :: [Screens.node_doc()]
  defp presented_nodes(%{"screen" => %{"elements" => elements}}), do: elements
  defp presented_nodes(_no_screen), do: []

  # The data form a started execution records for `opts[:scope]`.
  @spec scope_data(Scope.t() | nil) :: map() | nil
  defp scope_data(%Scope{} = scope), do: Scope.to_data(scope)
  defp scope_data(nil), do: nil

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

  # The Path a resumed execution runs, compiled the way the execution was
  # created: with the child recipe for a durable subchart child
  # (`opts[:child]`, the moduledoc's "A durable subchart child"), and as
  # `start/2` compiles a supplied Path otherwise.
  @spec compile_resumed(Document.t(), keyword()) ::
          {:ok, Compiled.t()} | {:error, {:path_document, term()}}
  defp compile_resumed(%Document{} = path, opts) do
    if Keyword.get(opts, :child, false) do
      case Subchart.child_compile(path) do
        {:ok, compiled} -> {:ok, compiled}
        {:error, findings} -> {:error, {:path_document, findings}}
      end
    else
      compile_path(path)
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
        with {:ok, compiled} <- compile_resumed(path, opts),
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

  # Every `myapp.step` in the Path configures exactly the buttons and the
  # questions of the screen it names (the moduledoc's "A screens document
  # the caller supplies"). A step whose screen is undeclared is
  # `declares_path_screens/2`'s, which runs first.
  @spec steps_agree(screens(), Document.t()) ::
          :ok
          | {:error,
             {:steps_disagree,
              [
                {Block.id(),
                 :button_not_on_screen
                 | :button_not_configured
                 | :question_not_on_screen
                 | :question_not_configured, String.t()}
              ]}}
  defp steps_agree({document, _admitted}, path) do
    disagreements =
      for %Block{type: "myapp.step"} = block <- Document.blocks(path),
          config = step_config(block),
          %{nodes: nodes} <- [Screens.screen(document, Map.get(config, "screen", ""))],
          disagreement <- step_disagreements(block.id, config, nodes),
          do: disagreement

    case disagreements do
      [] -> :ok
      found -> {:error, {:steps_disagree, found}}
    end
  end

  # A step's config as it compiles: a version 1 block's migrated, so its
  # `outcomes` is read as the `buttons` it resolves to.
  @spec step_config(Block.t()) :: map()
  defp step_config(%Block{type_version: 1, config: config}) do
    case ReturnableStep.migrate_config(1, config) do
      {:ok, migrated} -> migrated
      {:error, _reason} -> config
    end
  end

  defp step_config(%Block{config: config}), do: config

  @spec step_disagreements(Block.id(), map(), [Screens.node_doc()]) ::
          [{Block.id(), atom(), String.t()}]
  defp step_disagreements(id, config, nodes) do
    on_screen = screen_names(nodes)
    buttons = names(Map.get(config, "buttons"))
    questions = names(Map.get(config, "responses"))

    for {reason, name} <-
          missing(buttons, on_screen.buttons, :button_not_on_screen) ++
            missing(on_screen.buttons, buttons, :button_not_configured) ++
            missing(questions, on_screen.questions, :question_not_on_screen) ++
            missing(on_screen.questions, questions, :question_not_configured),
        do: {id, reason, name}
  end

  @spec missing([String.t()], [String.t()], atom()) :: [{atom(), String.t()}]
  defp missing(names, from, reason), do: for(name <- names, name not in from, do: {reason, name})

  @spec names(term()) :: [String.t()]
  defp names(list) when is_list(list), do: Enum.filter(list, &is_binary/1)
  defp names(_not_a_list), do: []

  # The button outcomes and the question keys on a screen, a container's
  # children included at any depth (a variant's candidates), in document
  # order and each once.
  @spec screen_names([Screens.node_doc()]) :: %{buttons: [String.t()], questions: [String.t()]}
  defp screen_names(nodes) do
    found = Enum.flat_map(nodes, &screen_name/1)

    %{
      buttons: for({:button, name} <- found, uniq: true, do: name),
      questions: for({:question, name} <- found, uniq: true, do: name)
    }
  end

  @spec screen_name(Screens.node_doc()) :: [{:button | :question, String.t()}]
  defp screen_name(%{"type" => "button", "outcome" => outcome}) when is_binary(outcome),
    do: [{:button, outcome}]

  defp screen_name(%{"type" => type, "key" => key} = node_doc) when is_binary(type) do
    own = if String.ends_with?(type, "_question"), do: [{:question, key}], else: []
    own ++ children(node_doc)
  end

  defp screen_name(node_doc), do: children(node_doc)

  @spec children(Screens.node_doc()) :: [{:button | :question, String.t()}]
  defp children(%{"elements" => inner}) when is_list(inner),
    do: Enum.flat_map(inner, &screen_name/1)

  defp children(%{"nodes" => inner}) when is_list(inner), do: Enum.flat_map(inner, &screen_name/1)
  defp children(_leaf), do: []

  # A view with a screen in it, as an error-shaped answer for `submit/3`:
  # pressing a button on an execution that has moved on is not a validation
  # failure, it is a stale page.
  @spec parked_on(view()) :: {:ok, view()} | {:error, :not_on_a_screen}
  defp parked_on(%{screen: nil}), do: {:error, :not_on_a_screen}
  defp parked_on(view), do: {:ok, view}

  # Which screen a position is resting in. The park of each screen the Path
  # names, looked for in the reading's active blocks; `nil` when the
  # execution is resting anywhere else. A park that is active on a screen
  # `screens` does not declare is an error naming that screen while the
  # execution runs (the moduledoc's "What a page draws is riddler's
  # answer"), and `nil` once it has stopped, when nothing is drawn of it.
  @spec screen_at(Execution.t(), map(), Document.t()) ::
          {:ok, String.t() | nil} | {:error, {:undeclared_screen, String.t()}}
  defp screen_at(%Execution{active: active, status: status}, screens, path) do
    active = MapSet.new(active)

    {declared, undeclared} =
      path
      |> parks()
      |> Enum.filter(fn {park, _key} -> MapSet.member?(active, park) end)
      |> Enum.map(fn {_park, key} -> key end)
      |> Enum.split_with(&Screens.screen(screens, &1))

    case {declared, undeclared, status} do
      {[key | _], _undeclared, _status} -> {:ok, key}
      {[], [key | _], :running} -> {:error, {:undeclared_screen, key}}
      {[], _undeclared, _status} -> {:ok, nil}
    end
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

  defp park(%Block{type: "myapp.step", id: id, config: config}),
    do: [{id, Map.get(config, "screen", "")}]

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

  # The moduledoc's "A secret question is sealed before the chart sees
  # it": the responses with every secret question's on `screen` sealed by
  # the app's sealer. A response riddler will not seal, or a sealer that
  # does not answer a sealed string, is `{:error, {:seal_secrets, reason}}`
  # and nothing is sent.
  @spec seal(screens(), Screens.screen(), map()) ::
          {:ok, map()} | {:error, {:seal_secrets, term()}}
  defp seal({_document, admitted}, %{key: key}, responses) do
    case Riddler.Screens.seal_secrets(admitted, key, responses, &Sealer.seal/1) do
      {:ok, sealed} -> {:ok, sealed}
      {:error, reason} -> {:error, {:seal_secrets, reason}}
    end
  end

  @doc """
  The keys of the secret questions among `nodes`, a container's children
  included at any depth - a variant's candidates, say, spelled `nodes` in a
  version 1 document and `elements` in a version 2 one.

  Public so that every reader of a screen's nodes finds a secret question
  by the same walk: `resolve/2` keeps them out of the view's responses, and
  the screen editor page holds their typed text wrapped
  (`StatifierExamplesWeb.ScreenEditorLive`'s "A secret question's
  response").
  """
  @spec secret_keys([Screens.node_doc()]) :: [String.t()]
  def secret_keys(nodes) when is_list(nodes) do
    Enum.flat_map(nodes, fn
      %{"type" => "secret_question", "key" => key} -> [key]
      %{"nodes" => inner} when is_list(inner) -> secret_keys(inner)
      %{"elements" => inner} when is_list(inner) -> secret_keys(inner)
      _node -> []
    end)
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
