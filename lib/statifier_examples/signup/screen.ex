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
          core.on_event  one per button: capture the answers, abandon

  Two params: which screen (a key in `priv/fixtures/signup_screens.json`)
  and how long before an unattended screen is abandoned. Everything else -
  how many handlers there are, what each captures, what event each listens
  for - is **derived from the element document**, which is the point:
  the screen's buttons are already declared once, and a composite that made
  an author re-declare them here would be a second place for them to drift.

  ## Where an answer lands

  `answers.<element_key>` (Riddler R10d), written by the firing handler's
  `capture` map - the key is the destination and the value is the path
  inside `_event.data` (`StatifierBlocks.Core.OnEvent`'s "The optional
  `capture` map"). So a screen's `text_question` keyed `first_name` writes
  `answers.first_name`, and the document never says so twice.

  A button may also declare `writes`, a `capture` map of its own, merged
  into the handler's - `answers.plan` on the two plan buttons, which is what
  the Path branches on.

  **`writes` does not record which button was pressed, and cannot.** A
  `capture` value is a path inside `_event.data`, never a literal: the pair
  compiles to `expr="_event.data.<source>"`. Both plan buttons declare the
  same pair, so both compile to the byte-identical assign, and what lands in
  `answers.plan` is whatever the **host** put in the event payload. What the
  field actually buys is which buttons write the path **at all** - `Back`
  declares no `writes`, so pressing it leaves `answers.plan` alone rather
  than overwriting it - and a place to say that this screen's press carries
  a `plan` field. The host contract that makes the Path's branch work is
  therefore unstated in both documents: an event named by
  `outcome_event/1` for a button that declares `writes` must carry those
  source fields in its payload. `docs/spikes/SF040-signup-skeleton.md`
  records that as the finding, and the ask under it.

  ## The park, and what it costs

  `core.await` needs an event name, and the arrangement has no ordinary
  event for it to wait for: every ordinary exit from a screen is a button,
  and a button is an interrupt. So the await names an event the host sends
  only to re-present a screen it has already shown, and its real job is to
  be somewhere the run can *sit* with a deadline on it. There is no
  "wait indefinitely, with a timeout" primitive in the `core.*` vocabulary
  today; the park is this app's way of not having one, and it is recorded
  as a finding rather than hidden here.

  ## What the deadline actually does, which is less than it sounds

  It abandons **the group**, not the run. The `timed_out` final is emitted
  at the end of the group's `body`, so a screen that times out completes
  exactly as a screen a button abandoned does: the Path advances to the
  next block and nothing downstream can tell the two apart - which is what
  `StatifierBlocks.Core.Await`'s own moduledoc says about two abandons on
  one rail. The difference is only in what was captured, and a timeout
  captures nothing. The param is labelled "Abandon after" because that is
  what it does to the group; read it as "stop waiting after", not as
  "end the signup". The same reading applies to a `Back` button: it
  abandons the group like any other, so it moves the Path *forward*.
  Giving a screen a real back edge, or a run a real give-up, needs the
  outcome surface finding 1 of the spike document says a composite does
  not have.

  ## Its outcomes are `core.group`'s, and that is not what was wanted

  A composite answers the outcomes of its expansion **root** and nothing
  deeper (`StatifierBlocks.Composite.derived_outcomes/2`), so this type
  declares one outcome, `done`. It was meant to declare one per button plus
  `timed_out`; it cannot, and neither can the same declaration held as
  `StatifierBlocks.Composite.Data`. `StatifierExamples.Signup.ScreenTest`
  asserts what it actually answers and the spike document carries the ask.
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
  reader of a compiled chart sees the name the button was authored with.
  """
  @spec outcome_event(String.t()) :: String.t()
  def outcome_event(outcome) when is_binary(outcome), do: "signup." <> outcome

  @doc """
  The id the park carries in the compiled document, for a `myapp.screen`
  block whose own id is `block_id`.

  `StatifierBlocks.Composite.expand/2` mints each member's id from the
  composite block's id and the local id `subtree/1` gave it, so the park of
  `blk_sp_account` is `blk_sp_account_park`. That is the one place this
  app can ask **which screen a parked run is sitting on**: the reading's
  active block ids are the run's position, and the park is the block a
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

  @spec handlers(Screens.screen() | nil) :: [Block.t()]
  defp handlers(nil), do: []

  defp handlers(screen) do
    capture = answer_capture(screen)

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
        "capture" => Map.merge(capture, writes(button))
      }
    )
  end

  # What the form collected: one pair per question on the screen, keyed by
  # its destination. `answer_keys/1` is `Screens`' own reading of which
  # nodes carry an answer, so the two modules cannot disagree about it.
  @spec answer_capture(Screens.screen()) :: %{optional(String.t()) => String.t()}
  defp answer_capture(screen) do
    Map.new(Screens.answer_keys(screen), &{"answers." <> &1, &1})
  end

  # What the press itself records. Absent on most buttons; the two plan
  # buttons declare `answers.plan`, which is what the Path branches on.
  @spec writes(Screens.node_doc()) :: %{optional(String.t()) => String.t()}
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
