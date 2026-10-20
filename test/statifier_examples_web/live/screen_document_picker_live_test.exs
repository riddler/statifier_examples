defmodule StatifierExamplesWeb.ScreenDocumentPickerLiveTest do
  @moduledoc """
  The chart editor's inspector offering the screens a document holds: a
  `myapp.screen` block's Config tab draws its `screen` param as a select
  over the keys of `StatifierExamples.Signup.Screens`, handed to the editor
  through its `field_candidates` assign.

  The options are read from the screens document, never spelled here, and
  the patron registration screen editor beside it offers no such picker.
  """

  use StatifierExamplesWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias StatifierExamples.Charts
  alias StatifierExamples.Signup.Screens

  describe "the candidates" do
    # Sabotage: keyed the candidates by the "timeout" param instead of
    # "screen"; this and the Config tab row went red, then reverted from a
    # copy.
    test "list every screen the document holds, labelled by its title" do
      assert %{{"myapp.screen", "screen"} => options} = Charts.field_candidates()

      assert options == Enum.map(Screens.screens(), &{&1.key, &1.title})
      assert length(options) > 1
    end
  end

  describe "the Config tab" do
    # Sabotage: dropped field_candidates from the editor's mount in
    # EditorLive; the select assertions went red, then reverted from a copy.
    test "draws a screen block's screen as a select over the held screens", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/editor?#{[doc: "signup_path"]}")

      view |> element("#sb-canvas") |> render_hook("select", %{"block-id" => "blk_sp_plan"})

      assert has_element?(view, "select[name='config[screen]']")

      for screen <- Screens.screens() do
        assert has_element?(view, "select[name='config[screen]'] option[value='#{screen.key}']")
      end

      assert has_element?(view, "select[name='config[screen]'] option[value='plan'][selected]")
    end

    # Sabotage: gave ScreenEditor.field_candidates/0 a list for the screen
    # block's "title"; the refute went red, then reverted from a copy.
    test "the screen editor's screen block draws no picker", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/screen-editor")

      block_id = insert_screen(view)
      element(view, "#sb-canvas") |> render_hook("select", %{"block-id" => block_id})

      assert has_element?(view, "[name='config[title]']")
      refute has_element?(view, "select[name='config[title]']")
      refute has_element?(view, "select[name='config[key]']")
    end
  end

  # One screen dragged onto the root's body, answering its block id: the
  # one the canvas did not draw before.
  defp insert_screen(view) do
    ids = fn ->
      ~r/data-block-id="([^"]+)"/
      |> Regex.scan(render(view), capture: :all_but_first)
      |> List.flatten()
      |> MapSet.new()
    end

    before = ids.()
    canvas = element(view, "#sb-canvas")
    canvas |> render_hook("insert-dragstart", %{"type" => "myapp.screens.screen"})

    canvas
    |> render_hook("insert-drop", %{
      "type" => "myapp.screens.screen",
      "parent-id" => "blk_pr_root",
      "slot" => "body",
      "index" => "0"
    })

    [id] = ids.() |> MapSet.difference(before) |> MapSet.to_list()
    id
  end
end
