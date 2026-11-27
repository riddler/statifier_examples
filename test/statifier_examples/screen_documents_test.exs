defmodule StatifierExamples.ScreenDocumentsTest do
  @moduledoc """
  Every screens document this app ships, and the one the screen editor
  walks out of its patron registration document, is a version 1 document,
  spelling a screen's children `nodes`, and the riddler release `mix.lock`
  resolves still admits each one and resolves it to the same content under
  the key it answers now, `elements`.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.Decode
  alias StatifierExamples.ScreenEditor.Try
  alias StatifierExamples.Signup.Screens

  @fixtures "priv/fixtures"

  # Every `*_screens.json` under the fixtures that is a screens document;
  # the editor's patron registration document is a block document, walked
  # below instead.
  defp shipped do
    for path <- Path.wildcard(Path.join(@fixtures, "*_screens.json")),
        document = path |> File.read!() |> Jason.decode!(),
        Map.has_key?(document, "screens"),
        do: {Path.basename(path), document}
  end

  defp walked do
    {:ok, block_document} =
      @fixtures
      |> Path.join("patron_registration_screens.json")
      |> File.read!()
      |> Decode.decode()

    {:ok, opts} = Try.options(block_document)
    {"patron_registration_screens.json (walked)", Keyword.fetch!(opts, :screens)}
  end

  # Every key a screen wrote, a variant candidate's included: a variant
  # resolves to the candidate whose condition holds.
  defp authored_keys(nodes) do
    Enum.flat_map(nodes, fn node -> [node["key"] | authored_keys(node["nodes"] || [])] end)
  end

  # Sabotage (run): made `StatifierExamples.Signup.Screens.admit/1` hand
  # riddler each screen's `nodes` under the version 2 key, `elements`, with
  # the document still at version 1. Riddler refused every document with
  # `document.other_version_spelling` and this went red on the first
  # admit. Restored from a copy.
  test "every screens document is version 1, is admitted, and resolves under elements" do
    documents = [walked() | shipped()]

    assert length(documents) == 7,
           "expected the six shipped screens documents and the walked one, got: " <>
             inspect(Enum.map(documents, &elem(&1, 0)))

    for {name, document} <- documents do
      assert document["schema_version"] == 1, "#{name} is not a version 1 document"

      assert {:ok, admitted} = Screens.admit(document)

      for screen <- document["screens"] do
        assert is_list(screen["nodes"]) and screen["nodes"] != []
        refute Map.has_key?(screen, "elements")

        assert {:ok, resolved, _diagnostics} =
                 Riddler.Screens.resolve_screen(admitted, screen["key"], %{})

        shown = Enum.map(resolved.elements, & &1.key)
        authored = authored_keys(screen["nodes"])

        assert shown != [], "#{name}'s #{screen["key"]} resolves to nothing"
        assert shown -- authored == [], "#{name}'s #{screen["key"]} resolves keys it never wrote"

        # Every element with no condition and no candidates is shown, in
        # the order the document wrote it.
        always =
          for node <- screen["nodes"],
              not Map.has_key?(node, "condition") and node["type"] != "variant",
              do: node["key"]

        assert Enum.filter(shown, &(&1 in always)) == always,
               "#{name}'s #{screen["key"]} drops or reorders an unconditional element"

        {:ok, answer} = Riddler.Journey.present(admitted, {:screen, screen["key"]}, %{})

        assert Enum.map(answer["screen"]["elements"], & &1["key"]) == shown
        refute Map.has_key?(answer["screen"], "nodes")
      end
    end
  end
end
