defmodule StatifierExamples.Library.Setup do
  @moduledoc """
  `myapp.setup`: the root of a branch library setup that can end more than
  one way.

  A setup's steps are `myapp.step` blocks (`StatifierExamples.Signup.ReturnableStep`),
  and a step finishes as `done` whichever button was pressed, so a setup
  whose root is a `core.sequence` declares the one root outcome `done` and
  how it went lives only in its `responses`. A parent that runs the setup
  as a child (`StatifierExamples.Library.Onboarding`) sees nothing of a
  child but the root outcome it finished with, so a setup that should be
  able to tell its parent "this needs a site visit" says it through this
  root instead.

  ## What an author configures

  The steps go in the `body` slot, in order, exactly as they went in a
  sequence's `body`. Beside them, three params name the one other way the
  setup can end:

    * `ending` - the outcome it ends with, such as `site_visit_needed`.
      Blank, the setup declares `done` alone and runs as a sequence would.
    * `ending_on` - the outcome of the button whose press can end it.
    * `ending_when` - a condition on that press, read from what the press
      carried (`_event.data.<question key>`), so the press ends the setup
      only when the answer calls for it. Blank, every press of the button
      ends it.

  The press is recorded first, as every press is: the step it belongs to
  writes its responses, and then the whole setup ends with `ending`,
  whatever steps are left. A setup whose steps all finish without that
  press ends with `done`.

  ## What it is made of

  A **composite**: a `core.group` whose `body` this type exposes as its own
  pass-through slot (`statifier_blocks`' ADR-0002 pass-through amendment),
  so the author's steps keep their own ids, and whose `interrupts` hold one
  `core.on_event` when an ending is named. The handler listens for the
  button's press, `StatifierExamples.Signup.Screen.outcome_event/1`, under
  the configured condition, abandons the group and names the outcome it
  finishes with under `finish_as` (the ADR's `C8`). `declared_outcomes/1`
  answers `done` and then the ending, from the block's own config (`C9`),
  which is what a compile for use as a child reads as the document's root
  outcomes, one top-level `<final>` each (ADR-0004's Amendment of
  2026-08-29, `C1`).

  The handler runs in a region of its own beside the body, so the step's
  own transition on the same press is taken too: the step records the
  press and the group then leaves with the ending.
  """

  use StatifierBlocks.Composite,
    name: "myapp.setup",
    params: [
      %{
        key: "ending",
        type: :string,
        label: "It can also end with",
        required?: false,
        default: ""
      },
      %{
        key: "ending_on",
        type: :string,
        label: "When this button is pressed",
        required?: false,
        default: ""
      },
      %{
        key: "ending_when",
        type: :expression,
        label: "And this holds of the press",
        required?: false,
        default: ""
      }
    ],
    slots: [%{name: "body", to: {"setup", "body"}, label: "Steps"}],
    sentence: "Run the setup's steps",
    palette_entry: %{
      label: "Setup",
      group: "Library",
      description:
        "Runs a setup's steps; a button's press may end it with an outcome of its own.",
      icon: "wrench-screwdriver",
      keywords: ["setup", "steps", "outcome", "ending"],
      order: 0
    },
    version: 1

  alias StatifierBlocks.Block
  alias StatifierExamples.Signup.Screen

  @doc """
  The group the author's steps land in, with the ending's handler on its
  rail when the config names an ending.

  Pure, and the ids are local. The group's `body` is written empty, which
  is what makes it a legal pass-through target.
  """
  @impl StatifierBlocks.Composite
  def subtree(params) do
    handlers =
      case ending(params) do
        nil -> []
        ending -> [handler(ending, params)]
      end

    [Block.new("core.group", id: "setup", slots: %{"body" => [], "interrupts" => handlers})]
  end

  @doc """
  The outcomes this block declares: `done`, then the ending when the config
  names one.

      iex> StatifierExamples.Library.Setup.declared_outcomes(%{
      ...>   "ending" => "site_visit_needed",
      ...>   "ending_on" => "test_reported"
      ...> })
      ["done", "site_visit_needed"]

      iex> StatifierExamples.Library.Setup.declared_outcomes(%{"ending" => ""})
      ["done"]
  """
  @impl StatifierBlocks.Composite
  def declared_outcomes(config) do
    case ending(config) do
      nil -> ["done"]
      ending -> ["done", ending]
    end
  end

  @spec handler(String.t(), map()) :: Block.t()
  defp handler(ending, params) do
    Block.new("core.on_event",
      id: "ending",
      config: %{
        "event" => Screen.outcome_event(text(params, "ending_on")),
        "payload" => "",
        "cond" => text(params, "ending_when"),
        "outcome" => "abandon",
        "finish_as" => ending,
        "capture" => %{}
      }
    )
  end

  # The ending a config names, or `nil` for a blank one or one with no
  # button to end on, so a config still being typed into answers no handler
  # rather than one listening for nothing.
  @spec ending(map()) :: String.t() | nil
  defp ending(config) do
    case {text(config, "ending"), text(config, "ending_on")} do
      {"", _button} -> nil
      {_ending, ""} -> nil
      {ending, _button} -> ending
    end
  end

  @spec text(map(), String.t()) :: String.t()
  defp text(config, key) do
    case Map.get(config, key) do
      value when is_binary(value) -> value
      _absent -> ""
    end
  end
end
