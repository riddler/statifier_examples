defmodule StatifierExamples.UpgradedScreensTest do
  @moduledoc """
  The library domains' screens documents this app stores under
  `priv/fixtures/` were version 1 documents and are rewritten as version 2
  by riddler's upgrade task, `mix riddler.upgrade`, run once over each file.
  The signup fixture is not among them: it stays a version 1 document.

  Two things are pinned for each rewritten file. It is the task's rewrite
  of the document it replaced: undoing the task's two edits - the version
  back to 1, each `elements` back to `nodes` - gives back, byte for byte,
  the version 1 file it replaced, whose SHA-256 is written below, and
  `Riddler.Screens.upgrade/1` of that version 1 document is the file as it
  now stands. And every screen of it presents the same answer the version 1
  document presented, read through `Riddler.Journey.present/3` against an
  empty root and against one that answers every question.
  """

  use ExUnit.Case, async: true

  alias Riddler.Screens.Document

  @fixtures "priv/fixtures"

  # The SHA-256 of each version 1 file before the task rewrote it.
  @version_one_digests %{
    "branch_onboarding_screens.json" =>
      "f48c5baca72401494bc587f50b3f65c248e4f8010b1576fe0b684c683ac4babf",
    "card_reader_setup_screens.json" =>
      "b8c707ef8d84dc2de57f47826c4fde8425886489e540faa5d12b34a1c61292cd",
    "catalogue_sync_screens.json" =>
      "9c87550820eff3f3b11d42411a24b8f71f45d47f7ed4a4a10800ca72d42b0856",
    "patron_registration_steps_screens.json" =>
      "18c9b23ad15e8e9b56c6353e6851a813af270be858cf9635c0b6af5fd620c3c4",
    "reading_list_import_screens.json" =>
      "edf7dc2e46bb91f5d7431f8c5ed57ef4e7b245bfe8df6c18d52439a1b132f516"
  }

  # Sabotage (run): put branch_onboarding_screens.json back at
  # schema_version 1 with its children still spelled elements; the version
  # assertion went red for that file. Restored from a copy. Sabotage (run):
  # retitled a screen of catalogue_sync_screens.json, a rewrite that
  # changed more than the task does; the digest assertion went red for that
  # file. Restored from a copy.
  test "each rewritten file is version 2 and the task's rewrite of the file it replaced" do
    for {name, digest} <- @version_one_digests do
      text = read(name)
      before = version_one(text)

      assert Jason.decode!(text)["schema_version"] == 2, "#{name} is not version 2"

      assert sha256(before) == digest,
             "#{name} is not the version 1 file it replaced with the task's two edits"

      assert Riddler.Screens.upgrade(Jason.decode!(before)) == {:ok, Jason.decode!(text)}
    end
  end

  # Sabotage (run): dropped the first element of the first screen of each
  # version 2 document before it was admitted; the first screen of
  # branch_onboarding_screens.json presented another answer and this went
  # red. Restored from a copy.
  test "each rewritten document presents every screen as the version 1 document did" do
    for name <- Map.keys(@version_one_digests) do
      text = read(name)
      after_upgrade = text |> Jason.decode!() |> admit!(name)
      before = text |> version_one() |> Jason.decode!() |> admit!(name)

      assert before.schema_version == 1 and after_upgrade.schema_version == 2

      for screen <- Jason.decode!(text)["screens"], root <- roots(screen) do
        key = screen["key"]
        {:ok, presented} = Riddler.Journey.present(after_upgrade, {:screen, key}, root)

        assert match?([_ | _], presented["screen"]["elements"]),
               "#{name}'s #{key} presents nothing"

        assert {:ok, presented} == Riddler.Journey.present(before, {:screen, key}, root),
               "#{name}'s #{key} presents another answer than its version 1 document did"
      end
    end
  end

  defp read(name), do: @fixtures |> Path.join(name) |> File.read!()

  # The task's two edits undone, on the text, so every other byte stays.
  defp version_one(text) do
    text
    |> String.replace(~s("schema_version": 2), ~s("schema_version": 1))
    |> String.replace(~s("elements": [), ~s("nodes": [))
  end

  defp sha256(text), do: :sha256 |> :crypto.hash(text) |> Base.encode16(case: :lower)

  defp admit!(decoded, name) do
    case Document.admit(decoded) do
      nil -> flunk("#{name} is not a document riddler admits")
      admitted -> admitted
    end
  end

  # An empty root, and one where every question on the screen holds an
  # answer, so a condition that reads a response is decided both ways.
  defp roots(screen) do
    answers =
      for element <- flatten(screen["elements"]),
          answer = answer(element),
          answer != nil,
          into: %{} do
        {element["key"], answer}
      end

    [%{}, %{"responses" => answers}]
  end

  defp flatten(elements) do
    Enum.flat_map(elements, fn
      %{"type" => "variant", "elements" => inner} -> flatten(inner)
      element -> [element]
    end)
  end

  defp answer(%{"type" => "boolean_question"}), do: true

  defp answer(%{"type" => "choice_question", "select" => "many", "answer_options" => [o | _]}),
    do: [o["value"]]

  defp answer(%{"type" => "choice_question", "answer_options" => [option | _]}),
    do: option["value"]

  defp answer(%{"type" => "text_question"}), do: "Riverbend"
  defp answer(_element), do: nil
end
