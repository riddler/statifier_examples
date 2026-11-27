defmodule StatifierExamples.ScreenDocumentsTest do
  @moduledoc """
  Every screens document this app ships, and the one the screen editor
  walks out of its patron registration document, is admitted by the
  riddler release `mix.lock` resolves and resolves to its content under the
  key it answers, `elements`. The signup fixture is a version 1 document,
  spelling a screen's children `nodes`, and stays one; every other is a
  version 2 document, spelling them `elements`.
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
  defp authored_keys(children) do
    Enum.flat_map(children, fn child ->
      [child["key"] | authored_keys(child["nodes"] || child["elements"] || [])]
    end)
  end

  # The version each document is at: the signup fixture stays at 1, and
  # every other screens document, the walked one included, is at 2.
  defp version("signup_" <> _name), do: 1
  defp version(_name), do: 2

  defp children_key(1), do: "nodes"
  defp children_key(2), do: "elements"

  # Sabotage (run): made `StatifierExamples.Signup.Screens.admit/1` hand
  # riddler each screen's `nodes` under the version 2 key, `elements`, with
  # the document still at version 1. Riddler refused every document with
  # `document.other_version_spelling` and this went red on the first
  # admit. Restored from a copy.
  test "every screens document is at its version, is admitted, and resolves under elements" do
    documents = [walked() | shipped()]

    assert length(documents) == 7,
           "expected the six shipped screens documents and the walked one, got: " <>
             inspect(Enum.map(documents, &elem(&1, 0)))

    for {name, document} <- documents do
      version = version(name)
      key = children_key(version)
      other = children_key(3 - version)

      assert document["schema_version"] == version,
             "#{name} is not a version #{version} document"

      assert {:ok, admitted} = Screens.admit(document)

      for screen <- document["screens"] do
        assert is_list(screen[key]) and screen[key] != []
        refute Map.has_key?(screen, other)

        assert {:ok, resolved, _diagnostics} =
                 Riddler.Screens.resolve_screen(admitted, screen["key"], %{})

        shown = Enum.map(resolved.elements, & &1.key)
        authored = authored_keys(screen[key])

        assert shown != [], "#{name}'s #{screen["key"]} resolves to nothing"
        assert shown -- authored == [], "#{name}'s #{screen["key"]} resolves keys it never wrote"

        # Every element with no condition and no candidates is shown, in
        # the order the document wrote it.
        always =
          for child <- screen[key],
              not Map.has_key?(child, "condition") and child["type"] != "variant",
              do: child["key"]

        assert Enum.filter(shown, &(&1 in always)) == always,
               "#{name}'s #{screen["key"]} drops or reorders an unconditional element"

        {:ok, answer} = Riddler.Journey.present(admitted, {:screen, screen["key"]}, %{})

        assert Enum.map(answer["screen"]["elements"], & &1["key"]) == shown
        refute Map.has_key?(answer["screen"], "nodes")
      end
    end
  end
end
