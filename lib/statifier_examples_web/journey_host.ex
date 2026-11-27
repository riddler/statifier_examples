defmodule StatifierExamplesWeb.JourneyHost do
  @moduledoc """
  The Journey page's host: the four callbacks of `Riddler.Journey.Host`,
  and the re-present function, that `RiddlerLiveView.Journey` drives
  `StatifierExamples.Signup.Journey` through.

  The component draws what riddler answers and hands back what the reader
  submits; every step is this module's, through `Signup.Journey`, which
  loads the execution from storage on every call. Nothing here keeps
  state.

  ## A Journey's name

  The component names a Journey by a string it never reads. Here the
  string is `journey/2`'s: the page's `?path=` key, when it names one, and
  the execution id from the URL, as a query string, so `parse/1` reads
  both back and a callback knows which Path and which options to run.
  For the branch onboarding the execution id is the onboarding's own, and
  each callback asks `StatifierExamples.Library.Onboarding.focus/1` again
  which execution to step, as the page did before the component.

  ## The answers

  `present/1`, `submit/2` and `back/2` answer riddler's answer itself, the
  one `Signup.Journey`'s view is drawn from (its `answer`). A submit the
  screen refuses answers its findings as `Riddler.Finding` structs, each
  carrying this app's words for it as its `author_message`
  (`StatifierExamples.Signup.Validation.check/2`), which is what the
  component draws beside the question. An execution, a Path or a name
  this module does not have is `{:error, :no_such_journey}`.

  A refusal of any other kind - a press `Signup.Journey` refuses for a
  reason that is not a finding - answers `{:error, []}`, so nothing drawn
  changes, and the page says why (below).

  ## Telling the page

  The component runs in the page's process, and so does every callback
  here. After a submit or a back request, each callback sends that process
  `{StatifierExamplesWeb.JourneyHost, {:view, view}}` with the view it
  stepped to, or `{StatifierExamplesWeb.JourneyHost, {:error, reason}}`,
  so the page draws what it shows beside the component - the execution
  id, a discarded press, the waiting reason and the receipt - from the
  same view. A caller that is not a page has the message in its mailbox
  and may ignore it.

  ## The outcome check

  The draft a re-present draws is the browser's, so `submit/2` is what
  bounds the outcome a reader presses: `Signup.Journey.submit/4` finds the
  pressed button among the screen's elements resolved with the submitted
  responses laid over what the chart holds, so a button the draft revealed
  is accepted only where the submitted responses reveal it too.

  ## The scope

  A Journey starts under the scope the page that starts it gives,
  `start/2`'s, and the execution records it
  (`StatifierExamples.Charts.Durable.scope/1`). Which kind of scope a
  Path's Journeys take is `scope_kind/1`'s: a branch library's for the
  branch onboarding and the setups, a patron's for patron registration,
  and the open scope every visitor holds for the signup Path.
  `start/2` refuses a scope of another kind.

  `present/1` answers the scope the presented execution records, so the
  component checks it with `StatifierExamplesWeb.JourneyAccess`, the
  access module for all of them. A setup the branch onboarding runs is a
  durable subchart child, and it records the onboarding's branch scope
  because the driver copies it into the child when it creates it: the
  check on a press inside a setup is asked against that copy. An
  execution of a library Path that records no scope - one started by code
  rather than by a page - is a Journey this module does not have. A
  signup Path execution that records none is answered under the open
  scope, and one that records another scope is refused, so an execution
  of a library Path named without its page key is not opened as the
  signup Path's.
  """

  @behaviour Riddler.Journey.Host

  alias Riddler.Journey.{Access, Scope}
  alias StatifierBlocks.Decode
  alias StatifierExamples.Charts.Durable
  alias StatifierExamples.Library.{Onboarding, RegistrationSteps, Setups}
  alias StatifierExamples.ScreenEditor.Try
  alias StatifierExamples.Signup.{Journey, Validation}
  alias StatifierExamplesWeb.JourneyAccess

  # The signup Path, named for a start: on the page it is the Path no
  # `?path=` names.
  @signup "signup_path"

  # Patron registration as the screen editor's document authored it, run
  # on the Path the editor's Try derives for it.
  @registration "patron_registration"
  @registration_file "patron_registration_screens.json"

  @doc """
  The scope a Journey of the signup Path runs under: the open scope every
  visitor holds (`StatifierExamplesWeb.JourneyAccess.open_scope/0`).
  """
  @spec scope() :: Scope.t()
  def scope, do: JourneyAccess.open_scope()

  @doc """
  The kind of scope a Journey of the Path the page key `path` names runs
  under (the moduledoc's "The scope"), `:error` for a key no list holds.

      iex> StatifierExamplesWeb.JourneyHost.scope_kind("catalogue_sync")
      {:ok, "branch"}
      iex> StatifierExamplesWeb.JourneyHost.scope_kind("patron_registration_steps")
      {:ok, "patron"}
      iex> StatifierExamplesWeb.JourneyHost.scope_kind(nil)
      {:ok, "open"}
  """
  @spec scope_kind(String.t() | nil) :: {:ok, String.t()} | :error
  def scope_kind(nil), do: {:ok, "open"}

  def scope_kind(key) when is_binary(key) do
    cond do
      key in [RegistrationSteps.key(), @registration] -> {:ok, "patron"}
      key == Onboarding.key() or key in Setups.keys() -> {:ok, "branch"}
      true -> :error
    end
  end

  @doc """
  The name `start/2` takes for the Path the page key `path` names:
  `"signup_path"` for the signup Path (`nil`), the key otherwise.
  """
  @spec path_name(String.t() | nil) :: String.t()
  def path_name(nil), do: @signup
  def path_name(key) when is_binary(key), do: key

  @doc """
  The scope of the Journey named `journey`: the one the execution a call
  steps records (the moduledoc's "The scope"), or
  `{:error, :no_such_journey}` for a Journey this module does not have.
  """
  @spec scope_of(String.t()) :: {:ok, Scope.t()} | {:error, :no_such_journey}
  def scope_of(journey) do
    with {:ok, path, _execution_id, {target, _opts}} <- target(journey),
         {:ok, kind} <- scope_kind(path),
         {:ok, scope} <- recorded_scope(path, target),
         :ok <- Access.check_kind(scope, kind) do
      {:ok, scope}
    else
      _refused -> {:error, :no_such_journey}
    end
  end

  @doc """
  The name of the Journey of the execution `execution_id` on the Path the
  page key `path` names, `nil` for the signup Path.

      iex> StatifierExamplesWeb.JourneyHost.journey(nil, "e-1")
      "execution=e-1"
      iex> StatifierExamplesWeb.JourneyHost.journey("patron_registration_steps", "e-1")
      "path=patron_registration_steps&execution=e-1"
  """
  @spec journey(String.t() | nil, String.t()) :: String.t()
  def journey(nil, execution_id) when is_binary(execution_id),
    do: URI.encode_query([{"execution", execution_id}])

  def journey(path, execution_id) when is_binary(path) and is_binary(execution_id),
    do: URI.encode_query([{"path", path}, {"execution", execution_id}])

  @doc """
  The page key and the execution id `journey/2` put in `journey`, or
  `:error` for a name it did not make.
  """
  @spec parse(String.t()) :: {:ok, String.t() | nil, String.t()} | :error
  def parse(journey) when is_binary(journey) do
    case URI.decode_query(journey) do
      %{"execution" => id} = query when id != "" -> {:ok, Map.get(query, "path"), id}
      _other -> :error
    end
  end

  def parse(_journey), do: :error

  @doc """
  The options every `StatifierExamples.Signup.Journey` call takes for the
  Path the page key `path` names: none for the signup Path (`nil`), the
  listed Path's otherwise, and `:error` for a key no list holds.
  """
  @spec path_options(String.t() | nil) :: {:ok, keyword()} | :error
  def path_options(nil), do: {:ok, []}

  def path_options(key) when is_binary(key) do
    cond do
      key == RegistrationSteps.key() -> {:ok, RegistrationSteps.options()}
      key == Onboarding.key() -> {:ok, Onboarding.options()}
      key == @registration -> registration_options()
      true -> Setups.options(key)
    end
  end

  @doc """
  Which execution a call steps for the Journey of `execution_id` on the
  page key `path`, and the options it takes: the onboarding's focus, asked
  now, for the branch onboarding, and `execution_id` with `opts` for every
  other Path.
  """
  @spec focus(String.t() | nil, String.t(), keyword()) ::
          {:ok, {String.t(), keyword()}} | {:error, term()}
  def focus(path, execution_id, opts) do
    if path == Onboarding.key(),
      do: Onboarding.focus(execution_id),
      else: {:ok, {execution_id, opts}}
  end

  @doc """
  Starts a Journey of the Path named `path` - a page key, or
  `"signup_path"` for the signup Path - under `scope`, which has to be of
  the kind `scope_kind/1` names for it. The execution records `scope`.
  """
  @impl Riddler.Journey.Host
  @spec start(String.t(), Scope.t()) ::
          {:ok, String.t(), Riddler.Journey.answer()} | {:error, :no_such_journey}
  def start(path, %Scope{} = scope) when is_binary(path) do
    key = if path == @signup, do: nil, else: path

    with {:ok, kind} <- scope_kind(key),
         :ok <- Access.check_kind(scope, kind),
         {:ok, opts} <- path_options(key),
         {:ok, execution_id} <-
           Journey.start(Durable.new_execution_id(), opts ++ [scope: scope]),
         {:ok, answer} <- answer(key, execution_id, opts) do
      {:ok, journey(key, execution_id), answer}
    else
      _refused -> {:error, :no_such_journey}
    end
  end

  @doc """
  Where the Journey named `journey` is, beside the scope it runs under
  (`scope_of/1`).
  """
  @impl Riddler.Journey.Host
  @spec present(String.t()) ::
          {:ok, Scope.t(), Riddler.Journey.answer()} | {:error, :no_such_journey}
  def present(journey) do
    with {:ok, path, execution_id} <- parse(journey),
         {:ok, opts} <- path_options(path),
         {:ok, scope} <- scope_of(journey),
         {:ok, answer} <- answer(path, execution_id, opts) do
      {:ok, scope, answer}
    else
      _refused -> {:error, :no_such_journey}
    end
  end

  @doc """
  Presses the submit's outcome with its responses (the moduledoc's "The
  outcome check").
  """
  @impl Riddler.Journey.Host
  @spec submit(String.t(), Riddler.Journey.submit()) ::
          {:ok, Riddler.Journey.answer()}
          | {:error, [Riddler.Finding.t()]}
          | {:error, :no_such_journey}
  def submit(journey, %{"outcome" => outcome, "responses" => responses}) do
    with {:ok, path, execution_id, {target, opts}} <- target(journey) do
      case Journey.submit(target, outcome, responses, opts) do
        {:ok, view} -> stepped(path, execution_id, view)
        {:invalid, view} -> refused(view, Validation.check(view.nodes, responses))
        {:error, reason} -> failed(reason)
      end
    end
  end

  @doc "Takes the Journey back from the screen the back request names."
  @impl Riddler.Journey.Host
  @spec back(String.t(), Riddler.Journey.back_request()) ::
          {:ok, Riddler.Journey.answer()}
          | {:error, [Riddler.Finding.t()]}
          | {:error, :no_such_journey}
  def back(journey, request) do
    with {:ok, path, execution_id, {target, opts}} <- target(journey) do
      case Journey.back(target, request, opts) do
        {:ok, view} -> stepped(path, execution_id, view)
        {:error, reason} -> failed(reason)
      end
    end
  end

  @doc """
  The screen the Journey named `journey` is on, presented again with the
  draft's responses laid over what the chart holds
  (`StatifierExamples.Signup.Journey.present_draft/3`). Nothing is sent and
  nothing is written.
  """
  @spec re_present(String.t(), %{required(String.t()) => term()}) ::
          {:ok, Riddler.Journey.answer()} | {:error, term()}
  def re_present(journey, %{"responses" => draft}) when is_map(draft) do
    with {:ok, _path, _execution_id, {target, opts}} <- target(journey) do
      case Journey.present_draft(target, draft, opts) do
        {:ok, answer} -> {:ok, answer}
        {:error, :execution_not_found} -> {:error, :no_such_journey}
        {:error, _reason} = error -> error
      end
    end
  end

  # The execution a submit, a back request or a re-present steps, asked
  # at the moment of the call.
  @spec target(String.t()) ::
          {:ok, String.t() | nil, String.t(), {String.t(), keyword()}}
          | {:error, :no_such_journey}
  defp target(journey) do
    with {:ok, path, execution_id} <- parse(journey),
         {:ok, opts} <- path_options(path),
         {:ok, focus} <- focus(path, execution_id, opts) do
      {:ok, path, execution_id, focus}
    else
      _refused -> {:error, :no_such_journey}
    end
  end

  # The scope the execution `target` records, read back from its data
  # form. A signup Path execution that records none is under the open
  # scope; an execution that records another scope is never read as one of
  # the signup Path's, so a page key left off the URL opens nothing.
  @spec recorded_scope(String.t() | nil, String.t()) :: {:ok, Scope.t()} | :error
  defp recorded_scope(path, target) do
    case Durable.scope(target) do
      {:ok, data} when is_map(data) -> Scope.from_data(data)
      {:ok, nil} when is_nil(path) -> {:ok, scope()}
      _none -> :error
    end
  end

  # Riddler's answer for where the Journey is now.
  @spec answer(String.t() | nil, String.t(), keyword()) ::
          {:ok, Riddler.Journey.answer()} | {:error, term()}
  defp answer(path, execution_id, opts) do
    with {:ok, view} <- current(path, execution_id, opts), do: {:ok, view.answer}
  end

  @spec current(String.t() | nil, String.t(), keyword()) ::
          {:ok, Journey.view()} | {:error, term()}
  defp current(path, execution_id, opts) do
    with {:ok, {presented, presented_opts}} <- focus(path, execution_id, opts),
         do: Journey.current(presented, presented_opts)
  end

  # After a press or a back request: the view it stepped to, or, for the
  # branch onboarding, the view of whatever the focus now is, since the
  # press that finishes a setup moves the onboarding on. A press the chart
  # refused moved nothing, so its view, which says so, is the one told.
  @spec stepped(String.t() | nil, String.t(), Journey.view()) ::
          {:ok, Riddler.Journey.answer()} | {:error, :no_such_journey}
  defp stepped(path, execution_id, view) do
    if path == Onboarding.key() and not Map.has_key?(view, :discarded) do
      {:ok, opts} = path_options(path)

      case current(path, execution_id, opts) do
        {:ok, refocused} -> told(refocused)
        {:error, reason} -> failed(reason)
      end
    else
      told(view)
    end
  end

  defp told(view) do
    tell({:view, view})
    {:ok, view.answer}
  end

  defp refused(view, findings) do
    tell({:view, view})
    {:error, findings}
  end

  defp failed(:execution_not_found) do
    tell({:error, :execution_not_found})
    {:error, :no_such_journey}
  end

  defp failed(reason) do
    tell({:error, reason})
    {:error, []}
  end

  # The moduledoc's "Telling the page".
  defp tell(message), do: send(self(), {__MODULE__, message})

  @spec registration_options() :: {:ok, keyword()} | :error
  defp registration_options do
    path =
      Path.join([
        Application.app_dir(:statifier_examples),
        "priv",
        "fixtures",
        @registration_file
      ])

    with {:ok, document} <- path |> File.read!() |> Decode.decode(),
         {:ok, opts} <- Try.options(document) do
      {:ok, opts}
    else
      _refused -> :error
    end
  end
end
