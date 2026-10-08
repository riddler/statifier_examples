defmodule UpgradeHost.Loans.Blocks.UntilReturned do
  @moduledoc """
  `myapp.until_returned`: runs its steps until the copy comes back.

  One `body` slot, run in order. The copy can come back at any point, in
  the middle of a step or after the last one: the event the block's
  `event` field names (`loan.returned` by default) finishes the block
  wherever it is, leaving whatever step was running. A body that runs out
  before the copy is back waits for it.

  It is written against `StatifierBlocks.BlockType` directly rather than
  through a base module, the way a host writes a block type the shipped
  vocabulary has no shape for. Its config check and its emission are built
  from the helpers the `core.*` types share: `StatifierBlocks.Core.Config`
  for the event name and the verdict, and `StatifierBlocks.Core.Emit` for
  the state, the chained body, the transition and the final.
  `StatifierBlocks.Core.Config` carries no published docs, from
  statifier_blocks 0.35.0 through 0.42.1; a production host calls it all the same, so this
  host does too, and a release that moves it is a finding here.
  """

  @behaviour StatifierBlocks.BlockType

  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.{Config, Emit}
  alias StatifierBlocks.Emission

  @default_event "loan.returned"

  @impl StatifierBlocks.BlockType
  def current_version, do: 1

  @impl StatifierBlocks.BlockType
  def slots(_config), do: [{"body", :any, "Steps"}]

  @impl StatifierBlocks.BlockType
  def config_schema(_config),
    do: [
      %{
        key: "event",
        type: :string,
        label: "Until this event arrives",
        required?: true,
        default: @default_event
      }
    ]

  @impl StatifierBlocks.BlockType
  def validate_config(config) do
    if Config.event_name?(Map.get(config, "event")),
      do: Config.verdict([]),
      else: Config.verdict([{"event", "must be an event name, like loan.returned"}])
  end

  @impl StatifierBlocks.BlockType
  def io(_config), do: %{kinds: [:step], slot_accepts: %{"body" => [:step]}}

  @impl StatifierBlocks.BlockType
  def palette_entry,
    do: %{
      label: "Until returned",
      group: "Library loan",
      description: "Runs its steps until the copy comes back.",
      icon: "arrow-uturn-left",
      keywords: ["loan", "return", "until"],
      order: 0,
      layout: :stack
    }

  @impl StatifierBlocks.BlockType
  def sentence(config), do: "Until " <> Map.get(config, "event", @default_event)

  @doc """
  A compound state running `body` in order into a `waiting` state, with
  the event on the block's own state so it is taken from anywhere inside:

      <state id="s_blk_LOAN" initial="s_blk_STEP1">
        <transition event="loan.returned" target="s_blk_LOAN__o_done" type="internal"/>
        <transition event="done.state.s_blk_STEP1" target="s_blk_STEP2" type="internal"/>
        <transition event="done.state.s_blk_STEP2" target="s_blk_LOAN__waiting" type="internal"/>
        ...the steps...
        <state id="s_blk_LOAN__waiting"/>
        <final id="s_blk_LOAN__o_done">...</final>
      </state>
  """
  @impl StatifierBlocks.BlockType
  def emit(%{config: config}, %Context{} = context) do
    with {:ok, waiting} <- Context.role_id(context, "waiting") do
      done = Context.done_id(context)
      {initial, chain, refs} = Emit.chain(Context.children(context, "body"), waiting)

      until =
        [event: Map.get(config, "event", @default_event), target: done, internal: true]
        |> Emit.transition()
        |> Emission.attribute_from_config("event", "event")

      {:ok,
       Emit.state(
         context.state_id,
         initial,
         [until | chain] ++ refs ++ [Emit.state(waiting, nil, []), Emit.final(done)]
       )}
    end
  end
end
