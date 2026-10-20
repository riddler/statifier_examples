defmodule StatifierExamples.ScreenEditor.TryTest do
  @moduledoc """
  The screen editor's Try action over a patron registration document of its
  own: two screens whose keys and outcomes the signup Path fixture has never
  heard of, run as a Journey on the Path `Try.path/1` derives for them.
  """

  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias StatifierBlocks.Block
  alias StatifierBlocks.Document
  alias StatifierExamples.Charts.Durable
  alias StatifierExamples.Repo
  alias StatifierExamples.ScreenEditor.Try
  alias StatifierExamples.ScreenEditor.Walk
  alias StatifierExamples.Signup.Journey

  doctest StatifierExamples.Signup.Screen, only: [parked_screen: 1]
  doctest StatifierExamples.Signup.Validation, only: [formats: 0]

  setup do
    :ok = Sandbox.checkout(Repo)
  end

  describe "path/1" do
    # Sabotage: made group/2 leave out the screen's questions from the
    # capture; the card_type pair went missing, then reverted.
    test "parks once per screen and captures every question on it" do
      {:ok, screens} = Walk.screen_document(registration())
      path = Try.path(screens)

      assert {:ok, _compiled} = Durable.compile(path, [])

      assert [card, welcome] = path.root.slots["body"]

      assert [_present, %Block{type: "core.await", config: %{"event" => park}}] =
               card.slots["body"]

      assert park == "signup.screen.card_choice.resumed"

      assert [%Block{config: %{"event" => "signup.card_chosen", "capture" => capture}}] =
               card.slots["interrupts"]

      assert capture == %{
               "responses.card_type" => "card_type",
               "responses.lending_rules" => "lending_rules",
               "responses.card_source" => ["const", "online"]
             }

      assert [%Block{config: %{"event" => "signup.registration_finished"}}] =
               welcome.slots["interrupts"]
    end
  end

  describe "start/1" do
    # Sabotage: made Journey's park/1 skip a core.await; the Journey started
    # on no screen and the card_choice assertion went red, then reverted.
    test "runs the authored screens as a Journey, invalid press first" do
      {:ok, %{execution_id: execution_id, opts: opts}} = Try.start(registration())

      {:ok, card} = Journey.current(execution_id, opts)
      assert %{key: "card_choice"} = card.screen
      assert card.state == "screen"
      assert Enum.map(card.nodes, & &1["key"]) == ~w(card_type lending_rules card_next)

      assert {:invalid, refused} =
               Journey.submit(execution_id, "card_chosen", %{"lending_rules" => true}, opts)

      assert refused.findings == [{"card_type", "is required"}]

      responses = %{"card_type" => "family", "lending_rules" => true}
      {:ok, welcome} = Journey.submit(execution_id, "card_chosen", responses, opts)

      assert %{key: "welcome"} = welcome.screen
      assert [%{"text" => "Your family card is on its way."} | _] = welcome.nodes

      assert welcome.responses == %{
               "card_type" => "family",
               "lending_rules" => true,
               "card_source" => "online"
             }

      {:ok, done} = Journey.submit(execution_id, "registration_finished", %{}, opts)
      assert done.state == "done"
      assert done.screen == nil
    end

    # Sabotage: made walk/1 answer the walk's refusals unwrapped; the
    # {:walk, _} match went red, then reverted.
    test "refuses a document the walk refuses, starting nothing" do
      stray = Block.new("myapp.screens.text", id: "blk_stray", config: %{"key" => "stray"})
      root = Block.new("core.sequence", id: "blk_root", slots: %{"body" => [stray]})

      assert {:error, {:walk, [{"blk_stray", _message}]}} = Try.start(Document.new(root))
    end

    # Sabotage: made start/1 leave the walked screens out of the Journey's
    # options; the start answered :undeclared_screens, then reverted.
    test "refuses a screen document riddler does not admit, starting nothing" do
      twice = screen("blk_try_twice", "card_choice", "Your card again", [])
      root = Block.new("core.sequence", id: "blk_root", slots: %{"body" => [twice, twice]})

      assert {:error, {:screens_document, [_ | _]}} =
               Try.start(Document.new(root, id: "doc_twice"))
    end
  end

  describe "Journey with a supplied Path" do
    # Sabotage: made Journey's resume/2 ignore opts[:path]; the current read
    # answered :chart_unknown, then reverted.
    test "refuses a Path that is not the one the Journey started on" do
      {:ok, %{execution_id: execution_id, opts: opts}} = Try.start(registration())
      {:ok, screens} = Walk.screen_document(registration())

      other = Try.path(Map.update!(screens, "screens", &Enum.take(&1, 1)))

      assert {:error, {:identity_mismatch, _stored, _supplied}} =
               Journey.current(execution_id, Keyword.put(opts, :path, other))
    end
  end

  # A patron registration block document authored in the screen palette:
  # the card the patron wants and the lending rules, then a welcome.
  defp registration do
    card =
      screen("blk_try_card", "card_choice", "Your card", [
        node("choice_question", "card_type", %{
          "label" => "Which card would you like?",
          "select" => "one",
          "style" => "radio",
          "required" => true,
          "answer_options" => ["standard=Standard card", "family=Family card"]
        }),
        node("boolean_question", "lending_rules", %{
          "label" => "I agree to the lending rules",
          "required" => true
        }),
        node("button", "card_next", %{
          "label" => "Continue",
          "outcome" => "card_chosen",
          "writes" => ["responses.card_source=online"]
        })
      ])

    welcome =
      screen("blk_try_welcome", "welcome", "Welcome", [
        node("text", "welcome_text", %{
          "text" => "Your {{ responses.card_type }} card is on its way."
        }),
        node("button", "welcome_done", %{
          "label" => "Finish",
          "outcome" => "registration_finished"
        })
      ])

    root = Block.new("core.sequence", id: "blk_try_doc_root", slots: %{"body" => [card, welcome]})
    Document.new(root, id: "doc_patron_registration")
  end

  defp screen(id, key, title, nodes) do
    Block.new("myapp.screens.screen",
      id: id,
      config: %{"key" => key, "title" => title},
      slots: %{"nodes" => nodes}
    )
  end

  defp node(type, key, config) do
    Block.new("myapp.screens." <> type,
      id: "blk_try_" <> key,
      config: Map.put(config, "key", key)
    )
  end
end
