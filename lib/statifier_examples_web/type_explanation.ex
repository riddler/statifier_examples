defmodule StatifierExamplesWeb.TypeExplanation do
  @moduledoc """
  What a block type is for, in a sentence or two a reader of the Plan view
  can take in at a glance.

  `statifier_blocks` has no callback that answers this yet: a palette
  entry carries a one-line `description` written for a picker, and nothing
  written for a reader who is looking at a block already placed. Until the
  package publishes such a callback, this module is the host's fixed text
  for the core types, and it is the ONE place that text lives - the Plan
  view's description region reads it, and anything else on this app's
  pages that explains a core type reads it from here rather than writing a
  second copy.

  A type this module has no text for - every host type, and a core type
  added to the package after this was written - falls back to its palette
  entry's `description`, and a block whose type the palette cannot resolve
  at all says so rather than guessing.

  ## Captions

  The map draws a one-line caption on the two structural containers whose
  shape needs saying: under a group's interrupt rules, and on the band
  over a branch's arms. `caption/1` is that text, and it lives here beside
  the longer explanations for the same reason they do: when the package
  publishes a per-type explanation, the host's fixed text is replaced in
  this one module. Every other type has no caption, and a leaf never
  carries one.
  """

  alias StatifierBlocks.ViewModel

  @core %{
    "core.sequence" =>
      "Runs the steps inside it one after another, top to bottom, and finishes when the last one does.",
    "core.group" =>
      "Holds steps together so its interrupt rules can watch them: while any step inside is running, a rule's event can abandon the group or resume it.",
    "core.resumable_group" =>
      "A group that remembers where it was: when a rule resumes it, it re-enters where it had reached, as its history setting says, rather than starting again from the top.",
    "core.branch" =>
      "Decides which way to go: it takes the first arm whose condition holds, in the order drawn, or Otherwise when none does. Only one arm runs.",
    "core.wait" => "Pauses for a fixed length of time, then carries on.",
    "core.send" =>
      "Sends an event. With a delay, the event is sent when the delay is up and the step finishes as soon as the send is set up.",
    "core.await" =>
      "Holds until a named event arrives. With a time limit it gives up when the limit passes, so it finishes one of two ways: received or timed out.",
    "core.on_event" =>
      "An interrupt rule: it waits for its event whichever step of its group is running, and when the event arrives it abandons the group or resumes it.",
    "core.raise" =>
      "Raises an event straight away for the interrupt rules of an enclosing group to hear.",
    "core.invoke" =>
      "Calls something the host provides and waits for it to answer, with an optional path for when the call fails.",
    "core.assign" => "Writes one value into the document's data.",
    "core.parallel" =>
      "Runs its lanes at the same time, in no particular order, and finishes as its completion setting says.",
    "core.foreach" =>
      "Runs the steps inside it once for each item of a list in the document's data, one item after another.",
    "core.map" =>
      "Runs another chart once for each item of a list, all at the same time, and waits for the whole batch.",
    "core.subchart" =>
      "Runs another chart and waits for it to finish, going on by the outcome that chart finished with.",
    "core.placeholder" =>
      "Marks a step the author has left unwritten on purpose: it does nothing when it runs, and the compile warns about it.",
    "core.drafts" =>
      "A shelf for steps the author has built but not placed: nothing on it is part of the flow, and nothing on it runs."
  }

  @captions %{
    "core.group" => "leave the group when they happen",
    "core.resumable_group" => "leave the group when they happen",
    "core.branch" => "only the first arm whose condition holds runs"
  }

  @unresolved "A block of a type this palette does not know, so nothing can be said about what it does."
  @undescribed "Its type gives no description of what it does."

  @doc """
  The explanation for `node`'s type: this module's fixed text for a core
  type, else the type's palette `description`, else a plain statement that
  its type says nothing more. A block the palette cannot resolve says so.
  """
  @spec explain(ViewModel.Node.t()) :: String.t()
  def explain(%ViewModel.Node{status: {:unresolvable, _reason}}), do: @unresolved

  def explain(%ViewModel.Node{type: type, entry: entry}) do
    case Map.fetch(@core, type) do
      {:ok, text} -> text
      :error -> described(Map.get(entry, :description))
    end
  end

  @doc """
  The one-line caption the map draws for a block of `type`: under a
  group's interrupt rules, or on a branch's band; `nil` for every other
  type. See the moduledoc's "Captions".
  """
  @spec caption(String.t()) :: String.t() | nil
  def caption(type) when is_binary(type), do: Map.get(@captions, type)

  @doc "The core type names this module carries its own text for."
  @spec core_types() :: [String.t()]
  def core_types, do: @core |> Map.keys() |> Enum.sort()

  @spec described(term()) :: String.t()
  defp described(description) when is_binary(description) do
    if String.trim(description) == "", do: @undescribed, else: description
  end

  defp described(_absent), do: @undescribed
end
