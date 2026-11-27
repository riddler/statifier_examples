defmodule StatifierExamples.ScreenEditor.Try do
  @moduledoc """
  The screen editor's Try action: a block document the editor holds, walked
  into a screen document and run as a Journey, so an author can fill in
  the screens they just placed.

  `start/1` is the whole of it. It walks the document
  (`StatifierExamples.ScreenEditor.Walk.screen_document/1`), derives a Path
  for the walked screens (`path/1`), and starts a Journey over both through
  `StatifierExamples.Signup.Journey`'s supplied-document path. Nothing is
  written to a file: the screen document and the Path live in what
  `start/1` answers, and the caller hands them to every
  `Journey.current/2` and `Journey.submit/4` after it.

  ## Why the Path is derived

  The signup Path fixture names the signup screens and listens for the
  signup buttons' outcomes, and a document authored in the editor - a
  patron registration form, say - has screen keys and outcomes of its own.
  So the Try action runs a Path of its own beside the document: the
  screens in the order they were placed, and every button on a screen
  moving the Journey on to the next one. The Journey is done once the last
  screen's button is pressed.

  It is built out of `core.*` blocks, one `core.group` per screen holding
  what a `myapp.screen` block expands to - present the screen, park on a
  `core.await`, and one `core.on_event` per outcome the screen's buttons
  declare - because a `myapp.screen` block reads its buttons out of the
  signup screens fixture, not out of the document the author wrote. Each
  handler captures every question on the screen into `responses.<key>`,
  as a `myapp.screen` handler does, plus the pressing button's `writes`.
  A secret question is captured like any other, and what its capture reads
  is the sealed form: `Journey.submit/4` seals the response before it
  raises the outcome, so the event never carries the text the patron typed.
  A Path with no branch has no use for an outcome other than "go on", so
  the handlers abandon their screen's group and the sequence moves on.
  """

  alias StatifierBlocks.Block
  alias StatifierBlocks.Document
  alias StatifierBlocks.Document.DatamodelEntry
  alias StatifierExamples.Charts.Durable
  alias StatifierExamples.ScreenEditor.Walk
  alias StatifierExamples.Signup.{Journey, Screen, Validation}

  @questions ["text_question", "choice_question", "boolean_question", "secret_question"]

  # The root every handler captures under, declared because an assign to a
  # root nothing declares raises error.execution rather than writing it.
  @responses %DatamodelEntry{
    id: "responses",
    description: "What the screens collected, keyed by element key."
  }

  @typedoc """
  A started Try: the execution id and the options every later Journey call
  over it takes - the walked screen document and the derived Path.
  """
  @type t :: %{execution_id: String.t(), opts: [screens: map(), path: Document.t()]}

  @doc """
  Walks `document`, derives its Path and starts a Journey over the two.

  `{:error, {:walk, refusals}}` for a document the walk refuses, with the
  walk's refusals; otherwise any refusal `Journey.start/2` answers, such
  as `{:error, {:screens_document, findings}}` for a screen document
  riddler does not admit with zero findings. Nothing is started for
  either.

  `{:error, {:unsupported_format, keys}}`, with nothing started, for a
  document whose text questions name a `format` the Journey's check has
  no message for (`StatifierExamples.Signup.Validation.formats/0`): the
  check raises on such a question at the first press, so the Try is
  refused before it starts rather than failing part way through.
  """
  @spec start(Document.t()) :: {:ok, t()} | {:error, term()}
  def start(%Document{} = document) do
    with {:ok, opts} <- options(document),
         {:ok, execution_id} <- Journey.start(Durable.new_execution_id(), opts) do
      {:ok, %{execution_id: execution_id, opts: opts}}
    end
  end

  @doc """
  The options every `StatifierExamples.Signup.Journey` call over
  `document`'s Try takes - the walked screen document and the derived
  Path - without starting anything: what `start/1` starts with, for a
  caller that runs the same document's Journey again by its execution id.
  Both are derived from `document` alone, so the same document answers
  the same options.

  `{:error, {:walk, refusals}}` and `{:error, {:unsupported_format, keys}}`
  as `start/1` refuses them.
  """
  @spec options(Document.t()) ::
          {:ok, [screens: map(), path: Document.t()]} | {:error, term()}
  def options(%Document{} = document) do
    with {:ok, screens} <- walk(document),
         :ok <- explained_formats(screens) do
      {:ok, [screens: screens, path: path(screens)]}
    end
  end

  @doc """
  The Path a screen document runs on: a `core.sequence` of one
  `core.group` per screen, in the document's order (see the moduledoc).
  """
  @spec path(map()) :: Document.t()
  def path(%{"id" => id, "screens" => screens}) when is_list(screens) do
    groups =
      screens
      |> Enum.with_index(1)
      |> Enum.map(fn {screen, position} -> group(screen, "blk_try_#{position}") end)

    root = Block.new("core.sequence", id: "blk_try_root", slots: %{"body" => groups})

    Document.new(root, id: "#{id}_path", datamodel: [@responses])
  end

  @spec walk(Document.t()) :: {:ok, map()} | {:error, {:walk, [Walk.refusal()]}}
  defp walk(document) do
    case Walk.screen_document(document) do
      {:ok, screens} -> {:ok, screens}
      {:error, refusals} -> {:error, {:walk, refusals}}
    end
  end

  # One screen: what `myapp.screen` expands to, with the screen's own
  # buttons and questions read off the screen itself.
  @spec group(map(), String.t()) :: Block.t()
  defp group(%{"key" => key} = screen, id) do
    elements = flatten(Map.get(screen, "elements", []))

    questions = for %{"type" => type, "key" => key} <- elements, type in @questions, do: key
    capture = Map.new(questions, &{"responses." <> &1, &1})

    handlers =
      elements
      |> Enum.filter(&(&1["type"] == "button"))
      |> Enum.uniq_by(& &1["outcome"])
      |> Enum.with_index(1)
      |> Enum.map(fn {button, position} ->
        handler(button, "#{id}_button_#{position}", capture)
      end)

    Block.new("core.group",
      id: id,
      slots: %{
        "body" => [
          Block.new("core.send",
            id: id <> "_present",
            config: %{"event" => Screen.present_event(key), "delay" => ""}
          ),
          Block.new("core.await",
            id: id <> "_park",
            config: %{"event" => Screen.park_event(key), "timeout" => ""}
          )
        ],
        "interrupts" => handlers
      }
    )
  end

  @spec handler(map(), String.t(), map()) :: Block.t()
  defp handler(button, id, capture) do
    Block.new("core.on_event",
      id: id,
      config: %{
        "event" => Screen.outcome_event(Map.fetch!(button, "outcome")),
        "payload" => "",
        "cond" => "",
        "outcome" => "abandon",
        "capture" => Map.merge(capture, Map.get(button, "writes", %{}))
      }
    )
  end

  # Every text question naming a format the Journey's check cannot
  # explain, by key, in document order.
  @spec explained_formats(map()) :: :ok | {:error, {:unsupported_format, [String.t()]}}
  defp explained_formats(%{"screens" => screens}) do
    keys =
      for screen <- screens,
          %{"type" => "text_question", "format" => format} = element <-
            flatten(Map.get(screen, "elements", [])),
          format not in Validation.formats(),
          do: Map.get(element, "key")

    case keys do
      [] -> :ok
      keys -> {:error, {:unsupported_format, keys}}
    end
  end

  # A screen's elements with every variant's candidates in among them, since
  # whichever candidate a reader is shown, its questions and buttons are the
  # screen's.
  @spec flatten([map()]) :: [map()]
  defp flatten(elements) do
    Enum.flat_map(elements, fn
      %{"type" => "variant", "elements" => inner} -> flatten(inner)
      element -> [element]
    end)
  end
end
