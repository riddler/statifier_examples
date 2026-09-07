defmodule StatifierExamples.CardAuth.AuthorizeWithDeadline do
  @moduledoc """
  `myapp.authorize_with_deadline`: the three-lane authorization arrangement,
  as one block an author fills in.

  This is a **composite** - `use StatifierBlocks.Composite`, params plus a
  pure `subtree/1` (sb ADR-0002 decision 5's amendment of 2026-09-07) - and
  it is one of the two this app ships as reference. The other is
  `StatifierExamples.Signup.GuardedStep`.

  ## What it stands for

  Exactly the arrangement `priv/fixtures/card_processing.json` spells out by
  hand: a `core.group` whose `body` holds a `core.send` arming the deadline
  and a `core.parallel` of three lanes, and whose `interrupts` hold the
  `core.on_event` listening for the deadline to fire. Eight params stand for
  the eight things about it an author actually chooses - how long the
  deadline is, what the three lanes are called, what each lane calls, and
  what happens when the deadline expires - and everything else is the shape.

  The hand-written arrangement in `card_processing.json` is **not** rewritten
  to use this. That document is the one place in this app a reader can see
  the primitives laid out, and it is what `priv/fixtures/card_processing_composite.json`
  is read against: the same arrangement, expressed the other way.

  ## The lane name is the root each lane records at

  A lane's name is a slot name on `core.parallel` (`lane_<name>`), so it is
  already a bare identifier, and the lane's call records its answer at
  `<lane name>.result`. That keeps the arrangement's writes derived from the
  params rather than hardwired: a chart that renames a lane renames the root
  it records at, and the fixture declares the three names it chose.

  ## What it does not have

  No slot of its own (`RQ-SF037-3`): a composite in this campaign exposes
  `slots/1 == []`, so what an author edits is the params and nothing else.
  Whoever wants the primitives uses the editor's Expand control, which
  replaces this block with the very blocks `subtree/1` answers - and the
  compiled chart does not move when they do, which
  `StatifierExamples.CompositesTest` asserts byte for byte.
  """

  use StatifierBlocks.Composite,
    name: "myapp.authorize_with_deadline",
    params: [
      %{
        key: "deadline",
        type: :duration,
        label: "Authorize within",
        required?: true,
        default: "15m"
      },
      %{
        key: "first_lane",
        type: :string,
        label: "First lane",
        required?: true,
        default: "fraud_review"
      },
      %{
        key: "first_call",
        type: :string,
        label: "First lane calls",
        required?: true,
        default: "myapp:risk_rating"
      },
      %{
        key: "second_lane",
        type: :string,
        label: "Second lane",
        required?: true,
        default: "balance_check"
      },
      %{
        key: "second_call",
        type: :string,
        label: "Second lane calls",
        required?: true,
        default: "myapp:balance_check"
      },
      %{
        key: "third_lane",
        type: :string,
        label: "Third lane",
        required?: true,
        default: "three_ds"
      },
      %{
        key: "third_call",
        type: :string,
        label: "Third lane calls",
        required?: true,
        default: "myapp:three_ds"
      },
      %{
        key: "outcome",
        type:
          {:select,
           [{"abandon", "Abandon - leave the group"}, {"resume", "Resume - re-enter the group"}]},
        label: "When it expires",
        required?: true,
        default: "abandon"
      }
    ],
    sentence: "Authorize within {deadline}, else {outcome}",
    palette_entry: %{
      label: "Authorize with a deadline",
      group: "Card processing",
      description: "Three authorization lanes under one deadline.",
      icon: "clock",
      keywords: ["authorize", "deadline", "parallel", "lanes"],
      order: 11
    },
    version: 1

  alias StatifierBlocks.Block

  # The event the deadline arms and the interrupt listens for. It is a fact
  # about the arrangement rather than a choice an author makes - the send and
  # the on_event have to name the same event or the deadline does nothing -
  # so it is written here once and is not a param.
  @deadline_event "card.authz_timed_out"

  @doc """
  The group, the deadline, the three lanes and the interrupt.

  Pure: the same params answer the same blocks, forever. The ids are
  **local** - `StatifierBlocks.Composite.expand/2` mints the document's ids
  from the composite block's own id - and they are positional (`lane_1`,
  `call_1`) rather than derived from the lane names, because a local id that
  moved when a label was retyped would move every state id in the compiled
  chart with it.
  """
  @impl StatifierBlocks.Composite
  def subtree(params) do
    lanes = [
      {"1", params["first_lane"], params["first_call"]},
      {"2", params["second_lane"], params["second_call"]},
      {"3", params["third_lane"], params["third_call"]}
    ]

    [
      Block.new("core.group",
        id: "authz",
        slots: %{
          "body" => [
            Block.new("core.send",
              id: "deadline",
              config: %{"event" => @deadline_event, "delay" => params["deadline"]}
            ),
            Block.new("core.parallel",
              id: "lanes",
              config: %{
                "lanes" => Enum.map(lanes, fn {_n, name, _call} -> name end),
                "complete" => "all"
              },
              slots: Map.new(lanes, &lane_slot/1)
            )
          ],
          "interrupts" => [
            Block.new("core.on_event",
              id: "timeout",
              config: %{
                "event" => @deadline_event,
                "payload" => "",
                "cond" => "",
                "outcome" => params["outcome"]
              }
            )
          ]
        }
      )
    ]
  end

  @spec lane_slot({String.t(), String.t(), String.t()}) :: {String.t(), [Block.t()]}
  defp lane_slot({position, name, call}) do
    {"lane_" <> name,
     [
       Block.new("core.group",
         id: "lane_" <> position,
         slots: %{
           "body" => [
             Block.new("core.invoke",
               id: "call_" <> position,
               config: %{
                 "invoke_type" => call,
                 "assign_to" => name <> ".result",
                 "params" => ""
               }
             )
           ]
         }
       )
     ]}
  end
end
