defmodule StatifierExamplesWeb.EventPhrasing do
  @moduledoc """
  The library world's event names, read as what happened: `copy.returned`
  reads as "the copy is returned".

  A block's sentence is the package's (`StatifierBlocks.ViewModel.sentence/1`),
  and it names an event by its name: "Send loan.closed", "Wait for
  copy.returned". A name is what a host sends and what a document listens
  for, so it is the right thing to author; it is not what a reader of the
  Plan view should have to decode. The Plan view's panel draws a block's
  sentence through `sentence/1` here, and its map and description region
  read `phrase/1`, so the two teaching documents read in words. The list keeps the package's
  sentence, the name as authored, and so do the places a name is a value
  rather than prose: a block's settings and what a document or a rule
  listens for.

  The words are the host's, keyed by event name, because they are a fact
  about the library world rather than about any block type. The package's
  own rewording seam, `StatifierBlocks.Describe.Phrasing`, rewords the
  lines of `StatifierBlocks.Describe.render/2`, a text this page does not
  draw, with one callback per kind of node or edge and none per event
  name. A name this table does not know is left as it is, so every other
  document on the page reads exactly as before.

  | A sentence that | reads as |
  |---|---|
  | sends an event | "Send word that" and the words |
  | waits for an event | "Wait until" and the words |
  | starts a rule with an event | "When" and the words |

  Only a name in one of those three places is an event, so only those are
  read as words. A known name anywhere else - a value a step sets, a
  decision's arm - is left as written.
  """

  alias StatifierBlocks.ViewModel
  alias StatifierBlocks.ViewModel.Node

  @phrases %{
    "copy.returned" => "the copy is returned",
    "copy.reported_lost" => "the copy is reported lost",
    "loan.closed" => "the loan is closed",
    "loan.renewed" => "the loan is renewed",
    "loan.overdue" => "the loan is overdue",
    "email.verified" => "the email address is verified",
    "guardian.consented" => "a guardian consents",
    "card.ready" => "the card is ready",
    "patron.asked_to_visit" => "the patron is asked to visit",
    "patron.welcomed" => "the patron is welcomed",
    "registration.abandoned" => "the registration is abandoned",
    "registration.deadline" => "the registration week is up"
  }

  # A name in event position: after "Send" (or a delayed "send"), after
  # "Wait for", or after a rule's "When". An event name is dotted words, so
  # the name runs until neither a word character nor a dot follows, and a
  # name that only starts like a known one is a different name. Compiled
  # once, with the module.
  @event_position ~r/\b(?:([Ss]end)|([Ww]ait) for|When) ([\w.]+)(?![\w.])/u

  @doc """
  The words for `event`, or `nil` for a name the library world does not
  use.
  """
  @spec phrase(String.t() | nil) :: String.t() | nil
  def phrase(event) when is_binary(event), do: Map.get(@phrases, event)
  def phrase(_other), do: nil

  @doc """
  `line` with every whole event name it knows in event position read as
  words; anything else in the line is left as it is.
  """
  @spec line(String.t()) :: String.t()
  def line(line) when is_binary(line),
    do: Regex.replace(@event_position, line, &phrased/4)

  @doc "A block's sentence, its event name read as words."
  @spec sentence(Node.t()) :: String.t()
  def sentence(%Node{} = node), do: node |> ViewModel.sentence() |> line()

  # One match of `@event_position`: the whole match, the "Send" or "send"
  # it opened with (or ""), the "Wait" or "wait" (or ""), and the name.
  @spec phrased(String.t(), String.t(), String.t(), String.t()) :: String.t()
  defp phrased(whole, send, wait, event) do
    case phrase(event) do
      nil -> whole
      words when send != "" -> send <> " word that " <> words
      words when wait != "" -> wait <> " until " <> words
      words -> "When " <> words
    end
  end
end
