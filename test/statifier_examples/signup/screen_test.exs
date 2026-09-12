defmodule StatifierExamples.Signup.ScreenTest do
  @moduledoc """
  `myapp.screen`: what the composite expands to, and the two limits the
  spike found by trying to build it (`docs/spikes/SF040-signup-skeleton.md`).

  The expansion cases are the ordinary obligation a composite carries - the
  arrangement is derived from the params and the element document, and it is
  read here out of `StatifierBlocks.Composite.expand/2` rather than
  transcribed. The last two cases are the spike's own: they assert what the
  type **does** answer where the bead asked for something else, so that a
  package change that lifted either limit would go red here and be noticed.

  A pure test: nothing here names LiveView.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, BlockType, Composite, Palette}
  alias StatifierBlocks.Composite.Data
  alias StatifierExamples.Charts
  alias StatifierExamples.Signup.{Screen, Screens}

  @plan %{"screen" => "plan", "timeout" => "1d"}

  defp ref, do: Palette.fetch(Charts.palette(), "myapp.screen") |> elem(1)

  defp expansion(config, id \\ "blk_x") do
    {members, _params} =
      Composite.expand!(Block.new("myapp.screen", id: id, config: config), ref())

    hd(members)
  end

  describe "it is registered, and it is a composite" do
    test "the palette this app hands the editor resolves it" do
      assert {:ok, Screen} = Palette.fetch(Charts.palette(), "myapp.screen")
      assert Composite.composite?(Screen)
    end

    test "the config schema is the two declared params, in order" do
      assert Enum.map(Screen.config_schema(%{}), & &1.key) == ["screen", "timeout"]
    end

    # `RQ-SF037-3`: a composite in this campaign exposes no slot of its own.
    test "it exposes no slot of its own" do
      assert Screen.slots(%{}) == []
    end

    test "the sentence names the screen and the deadline" do
      assert Screen.sentence(@plan) == "Show the plan screen, abandon after 1d"
    end
  end

  describe "the arrangement it expands to" do
    # Sabotage: changed the root from `core.group` to `core.sequence`. Two
    # cases went red - this one, and the Path's compile in
    # `StatifierExamples.Signup.PathTest`, because a sequence has no
    # `interrupts` slot for a handler to sit in and the document stops
    # compiling. The handler cases below stayed green: the handlers are still
    # built, they are just put somewhere nothing admits them, which is why the
    # compile is the case worth having. Reverted from a copy.
    test "the root is a group that presents the screen and then parks" do
      root = expansion(@plan)

      assert root.type == "core.group"

      assert Enum.map(root.slots["body"], &{&1.id, &1.type}) == [
               {"blk_x_present", "core.send"},
               {"blk_x_park", "core.await"}
             ]
    end

    test "the park carries the declared deadline" do
      [_present, park] = expansion(@plan).slots["body"]

      assert park.config == %{
               "event" => "signup.screen.plan.resumed",
               "timeout" => "1d"
             }
    end

    # Sabotage: made `handlers/1` drop the buttons whose node carries a
    # `condition`, which is two of the plan screen's three. Three cases went
    # red - this one, the capture case below, and the environment walk in
    # `StatifierExamples.Signup.PathTest`, which loses `answers.plan` with the
    # handlers that captured it. The distinctness case did NOT go red, and
    # that is worth knowing: it reads the outcomes off the element document
    # rather than off the expansion, so it cannot see a handler go missing.
    # Reverted from a copy.
    test "one interrupt handler per button the screen declares, in document order" do
      handlers = expansion(@plan).slots["interrupts"]

      assert Enum.map(handlers, & &1.id) == [
               "blk_x_button_1",
               "blk_x_button_2",
               "blk_x_button_3"
             ]

      assert Enum.map(handlers, & &1.config["event"]) == [
               "signup.personal_chosen",
               "signup.business_chosen",
               "signup.went_back"
             ]

      assert Enum.all?(handlers, &(&1.config["outcome"] == "abandon"))
    end

    # R10d: the destination is `answers.<element_key>` and the source is the
    # bare key inside `_event.data` - the direction `core.on_event`'s
    # "The optional `capture` map" states twice because it reads either way.
    test "each handler captures every question on the screen, keyed by destination" do
      [personal, _business, back] = expansion(@plan).slots["interrupts"]

      assert personal.config["capture"] == %{
               "answers.seats" => "seats",
               "answers.plan" => "plan"
             }

      # `went_back` declares no `writes`, so it records the form and nothing
      # about the press.
      assert back.config["capture"] == %{"answers.seats" => "seats"}
    end

    test "a screen with no writes on any button captures the questions alone" do
      [submit] = expansion(%{"screen" => "account", "timeout" => "1d"}).slots["interrupts"]

      assert submit.config["capture"] == %{
               "answers.first_name" => "first_name",
               "answers.email" => "email"
             }
    end

    # `subtree/1` runs behind `outcomes/1` and `io/1`, which the editor calls
    # against config it is still being typed into, so a half-typed screen key
    # has to expand rather than raise.
    test "a screen the element document does not declare expands with no handlers" do
      root = expansion(%{"screen" => "not_a_screen", "timeout" => "1d"})

      assert root.slots["interrupts"] == []
      assert length(root.slots["body"]) == 2
    end
  end

  describe "the two limits the spike found" do
    # THE BEAD ASKED FOR: one outcome slot per declared button, plus
    # `timed_out` (D13). WHAT THE PACKAGE ANSWERS: `done`, and only `done`.
    #
    # `StatifierBlocks.Composite.derived_outcomes/2` expands the subtree and
    # reads the outcomes of the expansion **root** alone - it descends no
    # further - so a composite rooted at `core.group` declares exactly what
    # `core.group` declares. The plan screen has three buttons; none of them
    # reaches this list.
    test "its outcomes are the group root's, not one per button" do
      assert BlockType.outcomes(ref(), @plan) == [{"done", "Done"}]
      assert length(Screens.outcomes(Screens.screen("plan"))) == 3
    end

    # And the same declaration held as data answers the same way, which is
    # the half of the question the bead asked to be tried rather than
    # assumed: `Data.outcomes/2` delegates to the same
    # `Composite.derived_outcomes/2`, so the data shape is not a way around
    # the root-only rule. An await-rooted twin is, and it is here to show
    # what the arrangement would have to be given up to get `timed_out`.
    test "a data-declared twin answers the root's outcomes too" do
      assert outcomes_of(%{
               "type" => "core.group",
               "id_suffix" => "screen",
               "config" => %{},
               "slots" => %{}
             }) == [{"done", "Done"}]

      assert outcomes_of(%{
               "type" => "core.await",
               "id_suffix" => "park",
               "config" => %{"event" => "signup.screen.plan.resumed", "timeout" => "1d"},
               "slots" => %{}
             }) == [{"received", "Received"}, {"timed_out", "Timed out"}]
    end
  end

  # A one-node data composite over `root`, resolved through a palette of its
  # own, answering `outcomes/1`.
  defp outcomes_of(root) do
    {:ok, state} =
      Data.declaration(%{
        "type_name" => "myapp.screen_twin",
        "version" => 1,
        "params" => [
          %{"key" => "screen", "type" => "string", "label" => "S", "default" => "plan"}
        ],
        "subtree" => [root]
      })

    palette = Palette.from_modules([{"myapp.screen_twin", {Data, state}}], core: true)

    BlockType.outcomes(elem(Palette.fetch(palette, "myapp.screen_twin"), 1), %{"screen" => "plan"})
  end
end
