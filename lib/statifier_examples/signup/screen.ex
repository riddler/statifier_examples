defmodule StatifierExamples.Signup.Screen do
  @moduledoc """
  `myapp.screen`: one screen of the signup wizard, as one block an author
  fills in.

  A **composite** - `use StatifierBlocks.Composite`, params plus a pure
  `subtree/1` (sb ADR-0002 decision 5's amendment of 2026-09-07) - and the
  block half of a Path (Riddler R10a). `StatifierExamples.Signup.Screens`
  is the element half: it says what is *on* a screen. This says what
  *happens* at one.

  ## The arrangement it stands for

  A `core.group` whose `body` presents the screen and then parks, and whose
  `interrupts` hold one `core.on_event` per button the screen declares:

      core.group
        body
          core.send   present the screen
          core.await  park, with the deadline
        interrupts
          core.on_event  one per button: capture the responses, abandon,
                         finish as the button's outcome

  Two params: which screen (a key in `priv/fixtures/signup_screens.json`)
  and how long before an unattended screen is abandoned. Everything else -
  how many handlers there are, what each captures, what event each listens
  for - is **derived from the element document**, which is the point:
  the screen's buttons are already declared once, and a composite that made
  an author re-declare them here would be a second place for them to drift.

  ## Where a response lands

  `responses.<element_key>` (Riddler R10d), written by the firing handler's
  `capture` map - the key is the destination and the value is the path
  inside `_event.data` (`StatifierBlocks.Core.OnEvent`'s "The optional
  `capture` map"). So a screen's `text_question` keyed `first_name` writes
  `responses.first_name`, and the document never says so twice.

  A button may also declare `writes`, a `capture` map of its own, merged
  into the handler's - `responses.plan` on the two plan buttons, which is what
  the Path branches on.

  ## `writes` records which button was pressed (2026-09-13, RQ-RF046-4)

  A `capture` value is told apart by its **shape**, and that is the package's
  rule rather than this app's: `StatifierBlocks.Core.OnEvent` (sb ADR-0002's
  Note of 2026-09-12, `N1`) reads a **string** as a path inside `_event.data`,
  compiling it to `expr="_event.data.<source>"`, and a **two-element
  `["const", value]` list** as a literal read out of the document itself,
  compiling it to `value` spelled as a predicator literal expression.

  This app takes the literal form on its two plan buttons. `plan_personal`
  declares `{"responses.plan": ["const", "personal"]}` and `plan_business`
  declares `["const", "business"]`, so the two buttons no longer compile to
  the same assign and what lands in `responses.plan` is the press itself -
  which is what the Path's `core.branch` reads. `Back` declares no `writes`
  at all, so pressing it still leaves `responses.plan` alone rather than
  overwriting it.

  **What this replaced, and what was true of it.** Until this date both plan
  buttons declared the same string source, `{"responses.plan": "plan"}`, and
  the app also carried a `payload` map on each of them putting `"personal"`
  or `"business"` into the pressed event. Of *that* declaration the claim
  this section used to make held: two identical string pairs compile to the
  byte-identical assign, so the press said nothing, and what reached
  `responses.plan` was whatever the **host** put in the payload - an unstated
  host contract without which the Path's branch took neither arm. The claim
  was written in the general form "a `capture` value is a path inside
  `_event.data`, never a literal", and in that form it stopped being true of
  the package at `statifier_blocks` 0.28.0, which is why it is confined here
  to the declaration it was ever about. The literal form closes the contract
  for these two buttons: no event the host sends has to carry a `plan` field
  any more, and the plan buttons declare no `payload`.
  `docs/spikes/SF040-signup-skeleton.md` carries the finding and this answer
  to it.

  ## The park, and what it costs

  `core.await` needs an event name, and the arrangement has no ordinary
  event for it to wait for: every ordinary exit from a screen is a button,
  and a button is an interrupt. So the await names an event the host sends
  only to re-present a screen it has already shown, and its real job is to
  be somewhere the execution can *sit* with a deadline on it. There is no
  "wait indefinitely, with a timeout" primitive in the `core.*` vocabulary
  today; the park is this app's way of not having one, and it is recorded
  as a finding rather than hidden here.

  ## What the deadline actually does, which is less than it sounds

  It abandons **the group**, not the execution. A screen that times out
  finishes as `timed_out`, one of the outcomes its block declares (the
  next section), and a timeout captures nothing. The Path routes
  `timed_out` through the block's `on_timed_out` slot, and the shipped Path
  leaves that slot empty, so an unanswered screen moves the Path on to its
  next block. The param is labelled "Abandon after" because that is what it
  does to the group; read it as "stop waiting after", not as "end the
  signup".

  ## Each block declares its own outcomes, and Back goes back (2026-09-18)

  `declared_outcomes/1` answers, from a block's own config, one outcome per
  button on its screen, in document order, and then `timed_out`. It is the
  per-instance declaration `statifier_blocks` 0.32.0 added (sb `ADR-0002`'s
  per-instance Amendment, `C9`), so the account, plan and confirm blocks
  declare three different lists and none declares a button another screen
  owns. Each handler names its button's outcome under `core.on_event`'s
  `finish_as` key (`C8`, `statifier_blocks` 0.31.0), which is what makes
  that outcome one its block can raise. A block therefore finishes as the
  button that was pressed or as `timed_out`, and opens one `on_<name>` slot
  per name for whatever should happen next.

  The shipped Path uses one of those slots. The plan block's `on_went_back`
  holds a second block showing the account screen, so pressing Back on the
  plan screen shows the account screen again and writes no `responses.plan`.
  It does not return to the plan screen: once the account screen shown
  again is submitted, the plan block has finished as `went_back`, and the
  Path goes on past it to the branch, which takes neither arm. A loop back
  to the plan screen is a navigation no core block expresses, and it is
  left open. `StatifierExamples.Signup.JourneyTest` presses Back and pins
  both halves.

  **What this replaced, and what was true of it.** Until this date the
  deadline section above ended: "The same reading applies to a `Back`
  button: it abandons the group like any other, so it moves the Path
  *forward*. Giving a screen a real back edge, or an execution a real
  give-up, needs the outcome surface finding 1 of the spike document says a
  composite does not have." It also said that a screen that times out
  "completes exactly as a screen a button abandoned does: the Path advances
  to the next block and nothing downstream can tell the two apart". And a
  section headed "Its outcomes are `core.group`'s, and that is not what was
  wanted" said: "A composite answers the outcomes of its expansion **root**
  and nothing deeper (`StatifierBlocks.Composite.derived_outcomes/2`), so
  this type declares one outcome, `done`. It was meant to declare one per
  button plus `timed_out`; it cannot, and neither can the same declaration
  held as `StatifierBlocks.Composite.Data`." All three were true at
  `statifier_blocks` 0.30.0, when a handler could not name the outcome it
  finished with and a composite's declared outcomes were one list for the
  whole type. They are confined here to that version. Two parts still hold:
  a declaration held as `StatifierBlocks.Composite.Data` has no
  per-instance spelling, and an execution still has no real give-up.
  `docs/spikes/SF040-signup-skeleton.md` carries the finding and this answer
  to it.
  """

  use StatifierBlocks.Composite,
    name: "myapp.screen",
    params: [
      %{
        key: "screen",
        type: :string,
        label: "Screen",
        required?: true,
        default: "account"
      },
      %{
        key: "timeout",
        type: :duration,
        label: "Abandon after",
        required?: true,
        default: "1d"
      }
    ],
    sentence: "Show the {screen} screen, abandon after {timeout}",
    palette_entry: %{
      label: "Screen",
      group: "Signup wizard",
      description: "Presents one wizard screen and waits for a button.",
      icon: "rectangle-stack",
      keywords: ["screen", "page", "wizard", "form"],
      order: 4
    },
    version: 1

  alias StatifierBlocks.Block
  alias StatifierExamples.Signup.Screens

  @doc """
  The event a button's press raises, for the outcome it declares.

  Outcome names are unique across the Path - `StatifierExamples.Signup.Path`
  is what holds them to it - so the event needs no screen in it, and a
  reader of a compiled chart sees the name the button was authored with. A
  screen shown again through a back edge is the same screen listening for
  the same events, not a second owner of them.
  """
  @spec outcome_event(String.t()) :: String.t()
  def outcome_event(outcome) when is_binary(outcome), do: "signup." <> outcome

  @doc """
  The id the park carries in the compiled document, for a `myapp.screen`
  block whose own id is `block_id`.

  `StatifierBlocks.Composite.expand/2` mints each member's id from the
  composite block's id and the local id `subtree/1` gave it, so the park of
  `blk_sp_account` is `blk_sp_account_park`. That is the one place this
  app can ask **which screen a parked execution is sitting on**: the reading's
  active block ids are the execution's position, and the park is the block a
  waiting screen is resting in. `StatifierExamples.Signup.Journey` is the
  caller, and the minting rule lives here rather than there because
  `subtree/1` above is what names the member.
  """
  @spec park_block_id(String.t()) :: String.t()
  def park_block_id(block_id) when is_binary(block_id), do: block_id <> "_park"

  @doc """
  The event the body parks on for `screen_key`. See the moduledoc on the
  park: the host sends it only to re-present a screen it already showed.
  """
  @spec park_event(String.t()) :: String.t()
  def park_event(screen_key) when is_binary(screen_key),
    do: "signup.screen." <> screen_key <> ".resumed"

  @doc """
  The event that asks the host to present `screen_key`.
  """
  @spec present_event(String.t()) :: String.t()
  def present_event(screen_key) when is_binary(screen_key),
    do: "signup.screen." <> screen_key <> ".present"

  @doc """
  The group, the presentation, the park, and one handler per button.

  Pure in the sense the record asks for - the same params answer the same
  blocks - though it reads a second shipped document to do it, which is a
  wider notion of purity than `StatifierExamples.Signup.GuardedStep`'s and
  is recorded in the spike document.

  A `screen` naming nothing in the element document expands to the group
  and the park with **no handlers**, rather than raising: `subtree/1` runs
  behind `outcomes/1` and `io/1`, which the editor calls against config it
  is still being typed into.

  The ids are local; `StatifierBlocks.Composite.expand/2` mints the
  document's ids from the composite block's own id. The handler ids are
  positional for the reason the lanes of
  `StatifierExamples.CardAuth.AuthorizeWithDeadline` are: an id derived
  from a label moves every state id in the compiled chart when the label
  is retyped.
  """
  @impl StatifierBlocks.Composite
  def subtree(params) do
    key = params["screen"]
    screen = Screens.screen(key)

    [
      Block.new("core.group",
        id: "screen",
        slots: %{
          "body" => [
            Block.new("core.send",
              id: "present",
              config: %{"event" => present_event(key), "delay" => ""}
            ),
            Block.new("core.await",
              id: "park",
              config: %{"event" => park_event(key), "timeout" => params["timeout"]}
            )
          ],
          "interrupts" => handlers(screen)
        }
      )
    ]
  end

  @doc """
  The outcomes this block declares: one per button on its screen, in
  document order, and then `timed_out`.

  Read from the block's own config, so each screen declares the buttons it
  has and no others. A screen the element document does not declare answers
  `[]` - a non-declaring instance, which is what the editor draws for a
  screen key that is still being typed.
  """
  @impl StatifierBlocks.Composite
  def declared_outcomes(%{"screen" => key}) when is_binary(key) do
    case Screens.screen(key) do
      nil -> []
      screen -> Screens.outcomes(screen) ++ ["timed_out"]
    end
  end

  def declared_outcomes(_config), do: []

  @spec handlers(Screens.screen() | nil) :: [Block.t()]
  defp handlers(nil), do: []

  defp handlers(screen) do
    capture = response_capture(screen)

    screen
    |> buttons()
    |> Enum.with_index(1)
    |> Enum.map(fn {button, position} -> handler(button, position, capture) end)
  end

  @spec handler(Screens.node_doc(), pos_integer(), map()) :: Block.t()
  defp handler(button, position, capture) do
    Block.new("core.on_event",
      id: "button_" <> Integer.to_string(position),
      config: %{
        "event" => outcome_event(Map.fetch!(button, "outcome")),
        "payload" => "",
        "cond" => "",
        "outcome" => "abandon",
        "finish_as" => Map.fetch!(button, "outcome"),
        "capture" => Map.merge(capture, writes(button))
      }
    )
  end

  # What the form collected: one pair per question on the screen, keyed by
  # its destination. `response_keys/1` is `Screens`' own reading of which
  # nodes carry a response, so the two modules cannot disagree about it.
  @spec response_capture(Screens.screen()) :: %{optional(String.t()) => String.t()}
  defp response_capture(screen) do
    Map.new(Screens.response_keys(screen), &{"responses." <> &1, &1})
  end

  # A button's own additional capture pairs, if it declares `writes`. Absent
  # on most buttons; the two plan buttons declare `responses.plan`, which is
  # what the Path branches on, and each declares it as its own literal - so
  # the pair IS a record of which button fired (the moduledoc's
  # "`writes` records which button was pressed" block states the rule).
  #
  # The map passes through as it stands, and there is no arm to add for the
  # literal form: `StatifierBlocks.Core.OnEvent` tells a source apart by
  # SHAPE (`N1`), so a string and a two-element `["const", value]` list are
  # both sources it admits. The value type is what says so - `String.t()` is
  # a path inside `_event.data`, and `[String.t()]` is the `["const", value]`
  # pair as this app's JSON documents hold it.
  @spec writes(Screens.node_doc()) :: %{optional(String.t()) => String.t() | [String.t()]}
  defp writes(button) do
    case Map.get(button, "writes") do
      %{} = pairs -> pairs
      _absent -> %{}
    end
  end

  @spec buttons(Screens.screen()) :: [Screens.node_doc()]
  defp buttons(%{nodes: nodes}) do
    for %{"type" => "button"} = node_doc <- nodes, do: node_doc
  end
end
