defmodule StatifierExamples.Signup.ScreenTest do
  @moduledoc """
  `myapp.screen`: what the composite expands to, and what each of its
  blocks declares it finishes as.

  The expansion cases are the ordinary obligation a composite carries - the
  arrangement is derived from the params and the element document, and it is
  read here out of `StatifierBlocks.Composite.expand/2` rather than
  transcribed. The declaration cases are the answer to the first of the two
  limits the spike found by trying to build it
  (`docs/spikes/signup-skeleton-spike.md`): since `statifier_blocks` 0.32.0
  each block declares its own buttons' outcomes and `timed_out`, read from
  its own config. The data-declared twin still answers what the spike found,
  because the per-instance spelling is a module composite's only.

  A pure test: nothing here names LiveView.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, BlockType, Compiled, Compiler, Composite, Palette}
  alias StatifierBlocks.Composite.Data
  alias StatifierExamples.Charts
  alias StatifierExamples.Signup.{Path, Screen}

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

    # Ruled by the operator, 2026-09-07: a leaf composite exposes no slot of
    # its own. 2026-09-18: it still declares no pass-through slot, and a
    # config naming no screen opens nothing; a named screen's `on_<name>`
    # slots are the declaration cases' below.
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
    # `StatifierExamples.Signup.PathTest`, which loses `responses.plan` with the
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

    # Each handler abandons the group AND names what it finishes as, under
    # `core.on_event`'s `finish_as` key, which is what makes a button's
    # outcome one its block can raise and so declare.
    #
    # Sabotage (2026-09-18): deleted the `"finish_as"` pair from `handler/3`.
    # This case went red, and so did every case that compiles the Path -
    # `StatifierExamples.Signup.PathTest`'s "green, with no warnings" among
    # them, answering `{:error, _}` with `:outcome_not_raisable` findings
    # for the declared button outcomes. Reverted from a copy.
    test "each handler finishes as its button's outcome" do
      handlers = expansion(@plan).slots["interrupts"]

      assert Enum.map(handlers, & &1.config["finish_as"]) == [
               "personal_chosen",
               "business_chosen",
               "went_back"
             ]
    end

    # The response-key rule: the destination is `responses.<element_key>` and
    # the source for a QUESTION is the bare key inside `_event.data` - the
    # direction `core.on_event`'s "The optional `capture` map" states twice
    # because it reads either way. The plan button's own pair is the other
    # shape, a `["const", value]` literal (se-luu, 2026-09-13); both land in
    # one map.
    test "each handler captures every question on the screen, keyed by destination" do
      [personal, _business, back] = expansion(@plan).slots["interrupts"]

      assert personal.config["capture"] == %{
               "responses.seats" => "seats",
               "responses.plan" => ["const", "personal"]
             }

      # `went_back` declares no `writes`, so it records the form and nothing
      # about the press.
      assert back.config["capture"] == %{"responses.seats" => "seats"}
    end

    test "a screen with no writes on any button captures the questions alone" do
      [submit] = expansion(%{"screen" => "account", "timeout" => "1d"}).slots["interrupts"]

      assert submit.config["capture"] == %{
               "responses.first_name" => "first_name",
               "responses.email" => "email"
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

  describe "what a button's `writes` map records" do
    # The blocking finding of the cold review on PR #98 was pinned here so the
    # prose could not drift back, and the general form it was written in HAD
    # drifted: at `statifier_blocks` 0.28.0 a `capture` source is told apart by
    # SHAPE (ADR-0002's Note of 2026-09-12, `N1`), a string being a path inside
    # `_event.data` and a `["const", value]` pair a literal read from the
    # document. `core/on_event.ex`'s own moduledoc calls the literal form "what
    # lets two handlers on one screen record which of them fired".
    #
    # se-luu (ruled by the operator, 2026-09-13) took the literal form up in
    # THIS app, so what these cases pin is the other side of the same
    # sentence: each plan button declares its OWN pair, the two no longer
    # compile to the same assign, and the press is what reaches
    # `responses.plan`. The host payload is no longer what carries it, and the
    # plan buttons declare no `payload` map at all. `Screen`'s `writes/1`
    # still passes the map through as it stands - the shape is the package's
    # to read, not this app's to branch on.
    #
    # Sabotage (2026-09-14): reverted both plan buttons' `writes` pairs in
    # `priv/fixtures/signup_screens.json` to the string form
    # `{"responses.plan": "plan"}` from a copy. This case went red on the
    # first assertion - `capture["responses.plan"]` read back `"plan"`
    # instead of `["const", "personal"]` - and so did the compiled-bytes case
    # below and the whole-map case above it. Reverted from the copy.
    test "each plan button captures its own literal, so the press says which fired" do
      [personal, business, _back] = expansion(@plan).slots["interrupts"]

      assert personal.config["capture"]["responses.plan"] == ["const", "personal"]
      assert business.config["capture"]["responses.plan"] == ["const", "business"]
      refute personal.config["capture"] == business.config["capture"]
    end

    # The case above reads `capture` at CONFIG level, where a source is the
    # value this app wrote into the element document. What that value MEANS
    # is the package's to decide, and `N1` decided it by SHAPE. A future note
    # that moved either arm would leave every config-level assertion here
    # green while the sentence they protect went false. This case reads the
    # COMPILED bytes instead, so what is pinned is the emission itself: the
    # plan pair compiles to the button's literal, and the questions still
    # compile to `expr="_event.data.<key>"`, the form
    # `StatifierExamples.Charts.Durable` states in its "`data` is the event's
    # payload" section. The literal is predicator's own string grammar,
    # double quotes and all, XML-escaped into the attribute.
    #
    # Sabotage (se-luu, 2026-09-13): in `statifier_blocks`'
    # `core/on_event.ex`, `defp source_expr([@const_tag, value])` returning
    # `"_event.data." <> value` instead of `literal(value)` - the literal arm
    # read as a path, which is the drift this case exists to catch. THIS CASE
    # WENT RED on the `plan_exprs` assertion and both config-level cases
    # above stayed GREEN, which is the whole reason this one is here. Second
    # sabotage, on this app's own side: reverted the two `writes` pairs in
    # `priv/fixtures/signup_screens.json` to the string form
    # `{"responses.plan": "plan"}` from a copy - this case went red on the
    # same assertion. The dependency was recompiled with
    # `MIX_ENV=test mix deps.compile statifier_blocks --force` before and
    # after, and both mutations were reverted from a copy.
    test "the compiled emission writes each plan button's own literal into responses.plan" do
      {:ok, %Compiled{scxml: scxml}} = Compiler.compile(Path.document(), Charts.palette())

      plan_exprs =
        Regex.scan(~r{<assign expr="([^"]*)" location="responses\.plan"/>}, scxml,
          capture: :all_but_first
        )

      # One per plan button, and each is that button's value read out of the
      # DOCUMENT - no path, so nothing the host sends is read at all.
      assert plan_exprs == [["&quot;personal&quot;"], ["&quot;business&quot;"]]

      # The other half of the shape rule, unchanged: every assign that is not
      # one of those two still reads out of `_event.data`, because every
      # question's capture pair is still a string source.
      all_exprs = Regex.scan(~r{<assign expr="([^"]*)"}, scxml, capture: :all_but_first)

      refute all_exprs == []

      assert Enum.all?(all_exprs -- plan_exprs, fn [expr] ->
               String.starts_with?(expr, "_event.data")
             end)
    end

    # What the field DOES buy, and the only thing it buys: which buttons
    # write the path at all.
    test "a button declaring no writes leaves responses.plan alone" do
      [_personal, _business, back] = expansion(@plan).slots["interrupts"]

      refute Map.has_key?(back.config["capture"], "responses.plan")
    end
  end

  describe "what each block declares it finishes as" do
    # One outcome per button on the block's own screen, in document order,
    # then `timed_out` - read from the block's config through
    # `declared_outcomes/1`, so the three screens declare three different
    # lists and none declares a button another screen owns. A screen the
    # element document does not declare is a non-declaring block.
    #
    # Sabotage (2026-09-18): made `declared_outcomes/1` answer the union of
    # every screen's buttons whatever the config. This case went red, and so
    # did the Path's compile in `StatifierExamples.Signup.PathTest`:
    # `{:error, _}` with ten `:outcome_not_raisable` findings - four, two and
    # four against the account, plan and confirm blocks, each refused the
    # names another screen owns. Reverted from a copy.
    test "each screen declares its own buttons and timed_out" do
      assert Screen.declared_outcomes(%{"screen" => "account"}) ==
               ["account_submitted", "timed_out"]

      assert Screen.declared_outcomes(@plan) ==
               ["personal_chosen", "business_chosen", "went_back", "timed_out"]

      assert Screen.declared_outcomes(%{"screen" => "confirm"}) ==
               ["signup_confirmed", "timed_out"]

      assert Screen.declared_outcomes(%{"screen" => "not_a_screen"}) == []
      assert Screen.declared_outcomes(%{}) == []
    end

    # What a reader of the block sees: the declared names as its outcomes,
    # each labelled by the member that raises it (a button's name is its own
    # label, the await's `timed_out` is "Timed out"), and one derived
    # `on_<name>` slot per name - the slot the Path's back edge sits in.
    #
    # Sabotage (2026-09-18): dropped the `++ ["timed_out"]` from
    # `declared_outcomes/1`. This case went red on both lists, the one above
    # went red, and so did the Journey's "a screen nobody answers": an
    # undeclared `timed_out` routes nowhere, so the timed-out screen no
    # longer moves the Path on. Reverted from a copy.
    test "its outcomes and its on_ slots are that block's own" do
      assert BlockType.outcomes(ref(), @plan) == [
               {"personal_chosen", "personal_chosen"},
               {"business_chosen", "business_chosen"},
               {"went_back", "went_back"},
               {"timed_out", "Timed out"}
             ]

      assert Screen.slots(@plan) == [
               {"on_personal_chosen", :zero_or_one, "personal_chosen"},
               {"on_business_chosen", :zero_or_one, "business_chosen"},
               {"on_went_back", :zero_or_one, "went_back"},
               {"on_timed_out", :zero_or_one, "Timed out"}
             ]

      assert Enum.map(Screen.slots(%{"screen" => "account"}), &elem(&1, 0)) ==
               ["on_account_submitted", "on_timed_out"]
    end

    # The data-declared twin is NOT a way around the root-only rule, and it
    # stays that way: a declaration held as data cannot hold a function, so
    # the per-instance spelling the module above uses is a module
    # composite's only (sb `ADR-0002`'s per-instance Amendment, `C9e`).
    # `Data.outcomes/2` delegates to `Composite.derived_outcomes/2`, which
    # for a non-declaring composite reads the expansion root's outcomes
    # alone. An await-rooted twin is shown beside it for what the
    # arrangement would have to give up to surface `timed_out` that way.
    #
    # The group-rooted twin carries a real `core.await` in its `body` - the
    # member whose `timed_out` the bead wanted surfaced. That is what makes
    # this case able to fail: an empty group would answer `done` under the
    # root-only rule AND under any deeper walk, so it would assert nothing.
    # With the await beneath it, `done` is evidence that the derivation did
    # not descend.
    test "a data-declared twin answers the root's outcomes too" do
      assert outcomes_of(%{
               "type" => "core.group",
               "id_suffix" => "screen",
               "config" => %{},
               "slots" => %{
                 "body" => [
                   %{
                     "type" => "core.await",
                     "id_suffix" => "park",
                     "config" => %{
                       "event" => "signup.screen.plan.resumed",
                       "timeout" => "1d"
                     },
                     "slots" => %{}
                   }
                 ]
               }
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
