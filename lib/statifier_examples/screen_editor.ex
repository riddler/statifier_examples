defmodule StatifierExamples.ScreenEditor do
  @moduledoc """
  The blocks editor as a screen editor: the palette, the profile and the
  field candidates a host page hands `StatifierBlocks.Editor` so an author
  builds a screen document - a patron registration form, say - out of
  blocks.

  Nothing here changes the editor. `StatifierExamples.Charts` is the chart
  editor's seam and this is the screen editor's beside it: the same
  component, given a different palette and told to draw fewer surfaces.

  ## The palette

  One block type per thing a screen document holds, each in the `Screens`
  group and each named for the document's own type under `myapp.screens.`:
  the screen itself (`key`, `title`, and a `nodes` slot), and the node
  types `heading`, `text`, `text_question`, `choice_question`,
  `boolean_question`, `button` and `variant`. Their fields are spelled as
  the document spells them. `registrations/0` lists them.

  The `core.*` vocabulary is registered underneath, because a document's
  root is a block and `core.sequence` is the plain ordered one: its `body`
  holds the document's screens in order. The profile's palette group list
  keeps the core types off the palette, so an author is offered screen
  blocks and nothing else.

  ## The profile

  A screen document is not a chart, so the surfaces that only mean
  something for a chart are left off (`profile/0`): the run pane
  (`run?: false`), the drawer's truth tables, declarations, fixtures and
  datamodel tabs, and the inspector's condition and fixtures tabs. The
  drawer keeps Findings and Source, and the inspector Config and Findings.

  ## The walk

  What the editor holds is a block document; what riddler reads is a
  screen document. `StatifierExamples.ScreenEditor.Walk.screen_document/1`
  walks the one into the other, screens and nodes in the order they were
  placed. `priv/fixtures/patron_registration_screens.json` is a block
  document this palette authors, and its walk is a screen document riddler
  admits with no finding.
  """

  alias StatifierBlocks.Editor
  alias StatifierBlocks.Palette

  alias StatifierExamples.ScreenEditor.{
    BooleanQuestion,
    Button,
    ChoiceQuestion,
    Heading,
    Screen,
    Text,
    TextQuestion,
    Variant
  }

  @group "Screens"

  @registrations [
    {"myapp.screens.screen", Screen},
    {"myapp.screens.heading", Heading},
    {"myapp.screens.text", Text},
    {"myapp.screens.text_question", TextQuestion},
    {"myapp.screens.choice_question", ChoiceQuestion},
    {"myapp.screens.boolean_question", BooleanQuestion},
    {"myapp.screens.button", Button},
    {"myapp.screens.variant", Variant}
  ]

  @doc """
  The screen block types, as `{type_name, module}` registrations, the
  screen first and the node types after it.
  """
  @spec registrations() :: [{String.t(), module()}]
  def registrations, do: @registrations

  @doc """
  The palette the screen editor is given: the screen block types over the
  `core.*` vocabulary a document's root needs.
  """
  @spec palette() :: Palette.t()
  def palette, do: Palette.from_modules(@registrations, core: true)

  @doc """
  The profile the screen editor is mounted with: the chart-only surfaces
  off, Source and Findings kept, and only the `Screens` palette group
  offered.
  """
  @spec profile() :: Editor.profile()
  def profile do
    %{
      drawer_tabs: [:findings, :source],
      inspector_tabs: [:config, :findings],
      palette_groups: [@group],
      run?: false
    }
  end

  @doc """
  The values the screen editor offers for a choice question's `style`: an
  open list, so a renderer's own style name can still be typed.
  """
  @spec field_candidates() :: %{optional({String.t(), String.t()}) => term()}
  def field_candidates do
    %{
      {"myapp.screens.choice_question", "style"} =>
        {:open,
         [
           {"radio", "Radio buttons"},
           {"dropdown", "Dropdown"},
           {"checkboxes", "Checkboxes"},
           {"list", "List"}
         ]}
    }
  end
end
