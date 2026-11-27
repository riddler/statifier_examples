defmodule StatifierExamples.Signup.ReturnableStepTest do
  @moduledoc """
  `myapp.step`, the plain returnable host step type, and Back through it:
  the type as the palette holds it, the patron registration Path built from
  it, and `StatifierExamples.Signup.Journey.back/3` walking that Path back
  and forth as a durable execution.

  Not async: durable executions step through the application's named
  `StatifierExamples.Charts.ExecutionLock`.
  """

  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias StatifierBlocks.{Block, BlockType, Document, Palette}
  alias StatifierExamples.Charts
  alias StatifierExamples.Charts.Durable
  alias StatifierExamples.Library.RegistrationSteps
  alias StatifierExamples.Repo
  alias StatifierExamples.Signup.{Journey, ReturnableStep, Screen}

  @name %{"first_name" => "Rosa", "email" => "rosa@example.com"}

  # The sha256 of each fixture's compiled chart, read at origin/main dd43466
  # before `myapp.step` was registered (2026-11-22). Neither fixture uses the
  # type, so registering it moves neither.
  @compiled %{
    "signup_path" => "a50eed087c7163bcc98c4c695297f308bbc9725fcd81dc2c49490de9e723d4c1",
    "patron_registration" => "2c89609a40bb782ff21623d0bf2e83f218c9e8e9b4bebfa9dcec40a67be497ff"
  }

  setup do
    :ok = Sandbox.checkout(Repo)
  end

  defp start_steps do
    opts = RegistrationSteps.options()
    {:ok, execution_id} = Journey.start("steps-#{System.unique_integer([:positive])}", opts)

    {execution_id, opts}
  end

  # The name and the card given, resting on the branch step.
  defp at_branch do
    {execution_id, opts} = start_steps()
    {:ok, _card} = Journey.submit(execution_id, "name_given", @name, opts)
    {:ok, branch} = Journey.submit(execution_id, "card_chosen", %{"card_type" => "family"}, opts)

    {execution_id, opts, branch}
  end

  defp key(%{screen: nil}), do: nil
  defp key(%{screen: screen}), do: screen.key

  defp value(%{nodes: nodes}, key),
    do: nodes |> Enum.find(&(&1["key"] == key)) |> Map.get("value")

  defp back_request(view), do: %{"screen" => key(view), "back" => true}

  describe "the type" do
    # Sabotage: removed the `"myapp.step"` entry from `Signup.block_types/0`.
    # This went red on the `Palette.fetch/2` match. Reverted from a copy.
    test "is in the host's palette beside the composite screen type, and declared returnable" do
      palette = Charts.palette()

      assert {:ok, ReturnableStep} = Palette.fetch(palette, "myapp.step")
      assert {:ok, Screen} = Palette.fetch(palette, "myapp.screen")
      assert BlockType.returnable?(ReturnableStep, %{"screen" => "patron_name"})
      refute BlockType.returnable?(Screen, %{"screen" => "account"})
    end

    # Sabotage: made `check_names/4`'s list clause skip the segment check.
    # The capitalised button was admitted and this went red. Reverted from
    # a copy.
    test "refuses a config that names no screen, no button, or a name that is not one segment" do
      assert ReturnableStep.validate_config(%{
               "screen" => "patron_name",
               "buttons" => ["name_given"],
               "responses" => ["first_name"]
             }) == :ok

      assert {:error, findings} =
               ReturnableStep.validate_config(%{
                 "screen" => "",
                 "buttons" => [],
                 "responses" => ["first name"]
               })

      assert Enum.map(findings, &elem(&1, 0)) == ["screen", "buttons", "responses"]

      assert {:error, [{"buttons", _message}]} =
               ReturnableStep.validate_config(%{"screen" => "s", "buttons" => ["Went"]})

      assert {:error, [{"buttons", _message}]} =
               ReturnableStep.validate_config(%{"screen" => "s", "buttons" => ["a", "a"]})
    end

    # Sabotage: made `migrate_config/2` answer the version 1 config as it
    # stood. The migrated config carried no `buttons` and this went red.
    # Restored from a copy.
    test "is at version 2, and a version 1 block's outcomes resolve as its buttons" do
      assert ReturnableStep.current_version() == 2

      v1 = %{
        "screen" => "patron_card",
        "outcomes" => ["card_chosen"],
        "responses" => ["card_type"]
      }

      assert ReturnableStep.migrate_config(1, v1) ==
               {:ok,
                %{
                  "screen" => "patron_card",
                  "buttons" => ["card_chosen"],
                  "responses" => ["card_type"]
                }}

      assert {:error, {:no_migration_from, 3}} = ReturnableStep.migrate_config(3, v1)

      block = %Block{type: "myapp.step", id: "blk_v1", type_version: 1, config: v1, slots: %{}}

      assert {:ok, ReturnableStep, %Block{config: config}} =
               Palette.resolve(Charts.palette(), block)

      assert config["buttons"] == ["card_chosen"]
      refute Map.has_key?(config, "outcomes")
    end

    # Sabotage: made `returnable?/1` answer `false`. The compiled chart had
    # no trail root and no back transition and this went red. Reverted from
    # a copy.
    test "compiles to a chart with a trail and the reserved back event" do
      {:ok, compiled} = Durable.compile(RegistrationSteps.document(), [])

      assert compiled.scxml =~ ~s(id="s_blk_prst_root__trail")
      assert compiled.scxml =~ ~s(event="#{Journey.back_event()}")
      assert compiled.scxml =~ ~s(event="signup.card_chosen")
      assert compiled.scxml =~ ~s(location="responses.card_type")
    end
  end

  describe "a Journey over the steps" do
    # Sabotage: made `back_offered?/2` in `Journey` answer `true` whatever
    # the reader said. The first step offered Back and this went red.
    # Reverted from a copy.
    test "offers no Back on the first step and Back on every step after it" do
      {execution_id, opts} = start_steps()

      {:ok, first} = Journey.current(execution_id, opts)
      assert key(first) == "patron_name"
      refute first.back

      {:ok, card} = Journey.submit(execution_id, "name_given", @name, opts)
      assert key(card) == "patron_card"
      assert card.back

      {:ok, branch} =
        Journey.submit(execution_id, "card_chosen", %{"card_type" => "family"}, opts)

      assert key(branch) == "patron_branch"
      assert branch.back
    end

    # Sabotage: sent `Screen.outcome_event("card_chosen")` in place of
    # `back_event/0` in `went_back/4`. The execution moved forward rather
    # than back and this went red. Reverted from a copy.
    test "goes back a step at a time, and a re-shown step carries its held values" do
      {execution_id, opts, branch} = at_branch()

      {:ok, card} = Journey.back(execution_id, back_request(branch), opts)
      assert key(card) == "patron_card"
      assert card.back
      assert value(card, "card_type") == "family"

      {:ok, name} = Journey.back(execution_id, back_request(card), opts)
      assert key(name) == "patron_name"
      refute name.back
      assert value(name, "first_name") == "Rosa"
      assert value(name, "email") == "rosa@example.com"
      assert name.responses == Map.put(@name, "card_type", "family")
    end

    # Journey's own check refuses a press that leaves a required question
    # out, so the press is sent to the stored execution directly, as a
    # host that skipped the check would send it.
    #
    # Sabotage: dropped the `!== undefined` guard from `assign/1` in
    # `ReturnableStep`. The press that left `email` out wrote it undefined
    # and this went red. Reverted from a copy.
    test "a step pressed again writes what the press carried and keeps what it left out" do
      {execution_id, opts, branch} = at_branch()
      {:ok, card} = Journey.back(execution_id, back_request(branch), opts)
      {:ok, _name} = Journey.back(execution_id, back_request(card), opts)

      {:ok, compiled} = Durable.compile(opts[:path], [])
      {:ok, {durable, run}} = Durable.resume(compiled, opts[:path], execution_id)

      {:ok, _moved} =
        Durable.send_event(durable, run, Screen.outcome_event("name_given"), %{
          "first_name" => "Rosalind"
        })

      {:ok, card_again} = Journey.current(execution_id, opts)
      assert key(card_again) == "patron_card"
      assert value(card_again, "card_type") == "family"
      assert card_again.responses["first_name"] == "Rosalind"
      assert card_again.responses["email"] == "rosa@example.com"
    end

    # Sabotage: made `back_presented?/1` answer `true` for an answer with no
    # moves. The done view offered Back and this went red. Reverted from a
    # copy.
    test "finishes once the last step is pressed, with nothing to go back to" do
      {execution_id, opts, _branch} = at_branch()

      {:ok, done} =
        Journey.submit(execution_id, "branch_chosen", %{"home_branch" => "central"}, opts)

      assert done.state == "done"
      refute done.back

      assert Journey.back(execution_id, %{"screen" => "patron_branch", "back" => true}, opts) ==
               {:error, :not_on_a_screen}
    end
  end

  describe "a back request is refused, and nothing is sent" do
    # Sabotage: made `back_offered/1` answer `:ok` for every view. The first
    # step's request was sent and answered `{:ok, view}`, and this went red.
    # Reverted from a copy.
    test "on the first step, where Back is not offered" do
      {execution_id, opts} = start_steps()

      assert Journey.back(execution_id, %{"screen" => "patron_name", "back" => true}, opts) ==
               {:error, :back_not_offered}
    end

    # Sabotage: made `on_screen/2` answer `:ok` for any key. The request
    # naming the screen the reader had left was sent and this went red.
    # Reverted from a copy.
    test "when the request names a screen other than the one the execution is on" do
      {execution_id, opts, _branch} = at_branch()

      assert Journey.back(execution_id, %{"screen" => "patron_card", "back" => true}, opts) ==
               {:error, {:stale_screen, "patron_branch"}}

      {:ok, view} = Journey.current(execution_id, opts)
      assert key(view) == "patron_branch"
    end

    # Sabotage: made `back_request/1` answer `{:ok, key}` for any decoded
    # map. The submit was taken as a back request and this went red.
    # Reverted from a copy.
    test "when riddler does not decode it as a back request" do
      {execution_id, opts, _branch} = at_branch()

      submit = %{"screen" => "patron_branch", "outcome" => "branch_chosen", "responses" => %{}}
      assert Journey.back(execution_id, submit, opts) == {:error, :not_a_back_request}

      assert {:error, {:back_request, [_ | _]}} =
               Journey.back(execution_id, %{"back" => true}, opts)

      {:ok, view} = Journey.current(execution_id, opts)
      assert key(view) == "patron_branch"
    end
  end

  describe "Journey start refuses a step that disagrees with its screen, and starts nothing" do
    # Sabotage: dropped the `:button_not_on_screen` term from
    # `step_disagreements/3` in `Journey`. The Path started and this went
    # red on the match. Restored from a copy.
    test "a configured button the screen does not carry" do
      opts =
        with_step("blk_prst_card", &Map.update!(&1, "buttons", fn b -> b ++ ["card_skipped"] end))

      assert start(opts) ==
               {:error,
                {:steps_disagree, [{"blk_prst_card", :button_not_on_screen, "card_skipped"}]}}
    end

    # Sabotage: dropped the `:button_not_configured` term from
    # `step_disagreements/3` in `Journey`. The Path started and this went
    # red on the match. Restored from a copy.
    test "a button on the screen the step does not configure" do
      opts = with_step("blk_prst_card", &Map.put(&1, "buttons", ["card_skipped"]))

      assert start(opts) ==
               {:error,
                {:steps_disagree,
                 [
                   {"blk_prst_card", :button_not_on_screen, "card_skipped"},
                   {"blk_prst_card", :button_not_configured, "card_chosen"}
                 ]}}
    end

    # Sabotage: dropped the `:question_not_on_screen` term from
    # `step_disagreements/3` in `Journey`. The Path started and this went
    # red on the match. Restored from a copy.
    test "a configured response the screen asks no question for" do
      opts = with_step("blk_prst_name", &Map.update!(&1, "responses", fn r -> r ++ ["phone"] end))

      assert start(opts) ==
               {:error, {:steps_disagree, [{"blk_prst_name", :question_not_on_screen, "phone"}]}}
    end

    # Sabotage: dropped the `:question_not_configured` term from
    # `step_disagreements/3` in `Journey`. The Path started and this went
    # red on the match. Restored from a copy.
    test "a question on the screen the step does not configure" do
      opts = with_step("blk_prst_name", &Map.put(&1, "responses", ["first_name"]))

      assert start(opts) ==
               {:error, {:steps_disagree, [{"blk_prst_name", :question_not_configured, "email"}]}}
    end

    # Sabotage: made `step_config/1` answer a version 1 block's config
    # unmigrated. Its `outcomes` read as no buttons, the screen's button
    # as unconfigured, and this went red on the start.
    # Restored from a copy.
    test "but starts a version 1 step whose outcomes are its screen's buttons" do
      opts =
        with_step(
          "blk_prst_branch",
          fn config ->
            {buttons, rest} = Map.pop(config, "buttons")
            Map.put(rest, "outcomes", buttons)
          end,
          1
        )

      assert {:ok, execution_id} = start(opts)
      assert {:ok, %{screen: %{key: "patron_name"}}} = Journey.current(execution_id, opts)
    end
  end

  # The registration steps' options, with the step `id`'s config passed
  # through `change` (and its stored version set to `version`).
  defp with_step(id, change, version \\ 2) do
    opts = RegistrationSteps.options()
    %Document{root: root} = path = opts[:path]

    body =
      for %Block{id: block_id} = block <- root.slots["body"] do
        if block_id == id,
          do: %{block | config: change.(block.config), type_version: version},
          else: block
      end

    Keyword.put(opts, :path, %Document{path | root: %{root | slots: %{"body" => body}}})
  end

  defp start(opts), do: Journey.start("steps-#{System.unique_integer([:positive])}", opts)

  describe "the signup Path" do
    # Sabotage: made `back_offered/1` answer `:ok` for every view. The plan
    # screen's request was sent and this went red. Reverted from a copy.
    test "offers no Back through the engine on any screen, and keeps its authored back edge" do
      {:ok, execution_id} = Journey.start("signup-#{System.unique_integer([:positive])}")

      {:ok, account} = Journey.current(execution_id)
      refute account.back

      {:ok, plan} =
        Journey.submit(execution_id, "account_submitted", %{
          "first_name" => "Ada",
          "email" => "ada@example.com"
        })

      assert key(plan) == "plan"
      refute plan.back
      assert Enum.any?(plan.nodes, &(&1["outcome"] == "went_back"))

      assert Journey.back(execution_id, %{"screen" => "plan", "back" => true}) ==
               {:error, :back_not_offered}
    end

    # Sabotage: pointed `Signup`'s `@reminder_block` at the signup Path's
    # reminder, so its loader rewrote that block's delay. The signup Path's
    # bytes moved and this went red. Reverted from a copy.
    test "and patron registration compile to the bytes they compiled to before myapp.step" do
      for {key, sha256} <- @compiled do
        {:ok, fixture} = Charts.fixture(key)
        {:ok, compiled} = Durable.compile(fixture.document, fixture.declare, fixture.datamodel)

        assert Base.encode16(:crypto.hash(:sha256, compiled.scxml), case: :lower) == sha256, key
      end
    end
  end
end
