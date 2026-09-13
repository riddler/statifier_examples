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

  ## The payload is this host's contract, and nothing checks it

  `StatifierExamples.Signup.Screen`'s moduledoc has the finding: a
  `capture` map's value is a path inside `_event.data`, never a literal, so
  what lands at `responses.<key>` is whatever **the host** put in the event's
  payload. This module is that host, so the contract is stated here in
  code:

      payload = the form's responses, keyed by element key,
                merged with the firing button's own `payload` map

  The first half feeds every question's capture pair (destination
  `responses.<key>`, source `<key>`). The second is how a press says
  something about *itself* - the plan buttons declare
  `"payload": {"plan": "business"}` and `{"plan": "personal"}`, which is
  what the Path's `core.branch` on `responses.plan` reads, and without it
  both buttons would write the same nothing. Neither document states this
  and neither can check it; `docs/spikes/SF040-signup-skeleton.md` carries
  it as the ask.

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
  """
  @type view :: %{
          execution_id: String.t(),
          screen: Screens.screen() | nil,
          nodes: [Screens.node_doc()],
          datamodel: map(),
          responses: %{optional(String.t()) => term()},
          status: Execution.status(),
          findings: [Validation.finding()]
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

  `{:error, :execution_not_found}` for an id nobody stored, and the storage
  layer's own refusals otherwise.
  """
  @spec current(String.t()) :: {:ok, view()} | {:error, term()}
  def current(execution_id) when is_binary(execution_id) do
    with {:ok, {{_durable, run}, _document}} <- Durable.resume(execution_id),
         {:ok, datamodel} <- datamodel(execution_id) do
      {:ok, view(execution_id, run, datamodel)}
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
    with {:ok, {{durable, run}, _document}} <- Durable.resume(execution_id),
         {:ok, datamodel} <- datamodel(execution_id),
         {:ok, drafted} <- parked_on(resolve(view(execution_id, run, datamodel), responses)),
         {:ok, button} <- button(drafted.nodes, outcome) do
      case Validation.validate(drafted.nodes, responses) do
        [] -> pressed(durable, run, execution_id, button, coerce(responses))
        findings -> {:invalid, %{drafted | findings: findings}}
      end
    end
  end

  @doc """
  The payload the press of `button` sends, for the responses `typed`.

  Public because it **is** the host contract the moduledoc describes, and a
  contract nothing can read is a contract nobody can check. `submit/3` is
  its only caller in this app; the spike document quotes it.
  """
  @spec payload(Screens.node_doc(), %{optional(String.t()) => term()}) :: map()
  def payload(button, typed) when is_map(button) and is_map(typed) do
    case Map.get(button, "payload") do
      %{} = literals -> Map.merge(typed, literals)
      _absent -> typed
    end
  end

  # The press itself. `Screen.outcome_event/1` is the event the compiled
  # `core.on_event` for this button is listening for, and the payload is
  # what its `capture` map reads out of.
  @spec pressed(Durable.t(), Execution.t(), String.t(), Screens.node_doc(), map()) ::
          {:ok, view()} | {:error, term()}
  defp pressed(durable, run, execution_id, button, typed) do
    event = Screen.outcome_event(Map.fetch!(button, "outcome"))

    with {:ok, {_durable, moved}} <-
           Durable.send_event(durable, run, event, payload(button, typed)),
         {:ok, datamodel} <- datamodel(execution_id) do
      {:ok, view(execution_id, moved, datamodel)}
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

  # The execution's own persisted datamodel, which is where the responses a screen
  # resolves against live once a chart is holding them.
  @spec datamodel(String.t()) :: {:ok, map()} | {:error, term()}
  defp datamodel(execution_id) do
    with {:ok, state} <- Durable.machine_state(execution_id) do
      {:ok, state.datamodel}
    end
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
