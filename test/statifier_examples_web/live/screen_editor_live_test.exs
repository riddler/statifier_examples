defmodule StatifierExamplesWeb.ScreenEditorLiveTest do
  @moduledoc """
  `/screen-editor` authored and tried: a patron registration document built
  in the editor with its insert and config events, then run as a Journey by
  the Try button, with no fixture file read or written for it.
  """

  use StatifierExamplesWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "the page" do
    # Sabotage: dropped the profile from the editor's mount; the core
    # types came back onto the palette, then reverted.
    test "mounts the editor with the screen palette and profile", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/screen-editor")

      assert html =~ ~s(data-group="Screens")
      refute html =~ ~s(<li data-type="core.)
      refute html =~ ~s(class="sb-run")
      assert has_element?(view, "#try")
      refute has_element?(view, "#try-journey")
    end

    # Sabotage: made refusals/1 answer [] for a screens-document refusal;
    # the empty-document Try drew no refusal, then reverted.
    test "lists why Try cannot start", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/screen-editor")

      twice = insert(view, "myapp.screens.screen", "blk_pr_root", "body", 0)
      configure(view, twice, %{"key" => "card_choice", "title" => "Your card"})
      again = insert(view, "myapp.screens.screen", "blk_pr_root", "body", 1)
      configure(view, again, %{"key" => "card_choice", "title" => "Your card again"})

      view |> element("#try") |> render_click()

      assert has_element?(view, "#try-refusals li")
      refute has_element?(view, "#try-journey")
    end
  end

  describe "a choice question, authored and tried" do
    # Sabotage: made typed/2 leave a posted response as the form's text;
    # the boolean question's tick reached the Journey as "true" and the
    # valid press was refused, then reverted. And: drew a choice of one as
    # checkboxes; the radio assertion went red, then reverted.
    test "presents it, refuses an invalid response, then reads the next answer", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/screen-editor")

      card = insert(view, "myapp.screens.screen", "blk_pr_root", "body", 0)
      configure(view, card, %{"key" => "card_choice", "title" => "Your card"})

      question = insert(view, "myapp.screens.choice_question", card, "nodes", 0)

      configure(view, question, %{
        "key" => "card_type",
        "label" => "Which card would you like?",
        "select" => "one",
        "style" => "radio",
        "required" => "true",
        "answer_options" => ["standard=Standard card", "family=Family card"]
      })

      rules = insert(view, "myapp.screens.boolean_question", card, "nodes", 1)

      configure(view, rules, %{
        "key" => "lending_rules",
        "label" => "I agree to the lending rules",
        "required" => "true"
      })

      next = insert(view, "myapp.screens.button", card, "nodes", 2)

      configure(view, next, %{
        "key" => "card_next",
        "label" => "Continue",
        "outcome" => "card_chosen"
      })

      welcome = insert(view, "myapp.screens.screen", "blk_pr_root", "body", 1)
      configure(view, welcome, %{"key" => "welcome", "title" => "Welcome"})

      text = insert(view, "myapp.screens.text", welcome, "nodes", 0)

      configure(view, text, %{
        "key" => "welcome_text",
        "text" => "Your {{ responses.card_type }} card is on its way."
      })

      # Try: the walk, the Journey, and the choice question presented.
      view |> element("#try") |> render_click()

      assert has_element?(view, "#try-journey")
      assert has_element?(view, ~s(#card_type input[type="radio"][value="standard"]))
      assert has_element?(view, ~s(#card_type input[type="radio"][value="family"]))
      assert render(view) =~ "Which card would you like?"

      # An invalid press: the rules ticked and no card chosen.
      view
      |> element("#try-responses")
      |> render_change(%{"responses" => %{"lending_rules" => "true"}})

      view |> element("#card_next") |> render_click()

      assert has_element?(view, "#try-finding-card_type", "is required")
      assert has_element?(view, "#card_type")

      # A valid press, and the Journey's next answer: the welcome screen.
      view
      |> element("#try-responses")
      |> render_change(%{"responses" => %{"card_type" => "family", "lending_rules" => "true"}})

      view |> element("#card_next") |> render_click()

      refute has_element?(view, "#try-findings")
      refute has_element?(view, "#card_type")
      assert has_element?(view, "#welcome_text", "Your family card is on its way.")
      assert view |> element("#try-collected") |> render() =~ "family"
    end
  end

  # The block ids the canvas draws, in page order.
  defp block_ids(view) do
    Regex.scan(~r/data-block-id="([^"]+)"/, render(view), capture: :all_but_first)
    |> List.flatten()
    |> MapSet.new()
  end

  # One palette drag onto a gap in a block's slot, answering the id of the
  # block it placed: the one block id the canvas did not draw before.
  defp insert(view, type, parent_id, slot, index) do
    before = block_ids(view)

    canvas(view) |> render_hook("insert-dragstart", %{"type" => type})

    canvas(view)
    |> render_hook("insert-drop", %{
      "type" => type,
      "parent-id" => parent_id,
      "slot" => slot,
      "index" => to_string(index)
    })

    [id] = view |> block_ids() |> MapSet.difference(before) |> MapSet.to_list()
    id
  end

  # A config edit, as the inspector's form posts it.
  defp configure(view, block_id, config) do
    canvas(view) |> render_hook("config-change", %{"block-id" => block_id, "config" => config})
  end

  defp canvas(view), do: element(view, "#sb-canvas")
end
