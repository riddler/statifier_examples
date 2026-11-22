defmodule StatifierExamples.Library.SetupsTest do
  @moduledoc """
  The three branch library setups: the one list, the root outcomes each
  document declares, each step's config against the screen it names, and
  each setup run alone as a durable Journey with Back between its steps.

  Not async: durable executions step through the application's named
  `StatifierExamples.Charts.ExecutionLock`.
  """

  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias StatifierBlocks.{Block, Document}
  alias StatifierExamples.Library.{RegistrationSteps, Setups}
  alias StatifierExamples.Repo
  alias StatifierExamples.Signup.Journey

  # Each setup's walk, a press per step: the screen it rests on, the
  # outcome pressed and what the press carried.
  @walks %{
    "catalogue_sync" => [
      {"catalogue_source", "feed_chosen", %{"catalogue_feed" => "union_catalogue"}},
      {"catalogue_schedule", "schedule_chosen", %{"sync_schedule" => "nightly"}},
      {"catalogue_contact", "sync_confirmed", %{"sync_contact_email" => "desk@example.com"}}
    ],
    "reading_list_import" => [
      {"reading_list_source", "format_chosen", %{"reading_list_format" => "spreadsheet"}},
      {"reading_list_when", "term_given", %{"reading_list_term" => "Spring term"}},
      {"reading_list_titles", "import_confirmed", %{"reading_list_holds" => "place_holds"}}
    ],
    "card_reader_setup" => [
      {"reader_model", "model_chosen", %{"reader_kind" => "desk_reader"}},
      {"reader_place", "location_given", %{"reader_location" => "Beside the returns slot"}},
      {"reader_test", "test_reported", %{"reader_test_result" => "card_read"}}
    ]
  }

  setup do
    :ok = Sandbox.checkout(Repo)
  end

  defp start(key) do
    {:ok, opts} = Setups.options(key)

    {:ok, execution_id} =
      Journey.start("setup-#{key}-#{System.unique_integer([:positive])}", opts)

    {execution_id, opts}
  end

  defp screen_key(%{screen: nil}), do: nil
  defp screen_key(%{screen: screen}), do: screen.key

  describe "the one list" do
    # Sabotage: dropped the card-reader row from `@setups`. The list named
    # two keys and this went red. Reverted from a copy.
    test "names the three setups, each by its key and its document id" do
      assert Setups.keys() == ["catalogue_sync", "reading_list_import", "card_reader_setup"]

      for key <- Setups.keys() do
        assert {:ok, %Document{id: id} = document} = Setups.document(key)
        assert id == "bdoc_" <> key
        assert Setups.fetch_document(id) == {:ok, document}
      end
    end

    # Sabotage: dropped the `^document_id` pin in `fetch_document/1`, so it
    # answered the first setup for any id. The unlisted id resolved and this
    # went red. Reverted from a copy.
    test "answers :error for a key or a document id it does not list" do
      assert Setups.options("branch_closure") == :error
      assert Setups.document("branch_closure") == :error
      assert Setups.fetch_document("bdoc_branch_closure") == :error
      assert Setups.fetch_document(RegistrationSteps.document().id) == :error
    end

    # Sabotage: made `outcomes/1` answer the interface's `references` (`[]`)
    # in place of its declared outcomes. This went red. Reverted from a copy.
    test "each document declares the root outcome done, compiled for use as a child" do
      for key <- Setups.keys() do
        assert Setups.outcomes(key) == {:ok, ["done"]}
      end
    end
  end

  describe "each step's config agrees with the screen it names" do
    # Sabotage: changed `"outcomes": ["schedule_chosen"]` on the catalogue
    # sync's schedule step to `["schedule_given"]`. This went red naming
    # the block. Restored from a copy.
    test "its outcomes are the screen's buttons' and its responses the screen's questions'" do
      for {name, %Document{} = document, screens} <- paths() do
        steps = for %Block{type: "myapp.step"} = block <- Document.blocks(document), do: block
        assert steps != [], "#{name} has no myapp.step block"

        for %Block{id: id, config: config} <- steps do
          screen = Enum.find(screens["screens"], &(&1["key"] == config["screen"]))
          assert screen, "#{name} #{id} names a screen its screens document does not declare"

          assert Enum.sort(config["outcomes"]) == screen |> outcomes() |> Enum.sort(),
                 "#{name} #{id}'s outcomes are not its screen's buttons'"

          assert Enum.sort(Map.get(config, "responses", [])) ==
                   screen |> questions() |> Enum.sort(),
                 "#{name} #{id}'s responses are not its screen's questions'"
        end

        assert Enum.sort(Enum.map(steps, & &1.config["screen"])) ==
                 Enum.sort(Enum.map(screens["screens"], & &1["key"])),
               "#{name} declares a screen no step shows"
      end
    end

    # The boolean answer is not converted on the Journey page, so no setup
    # asks one.
    #
    # Sabotage: made the card reader's test-card question a
    # `boolean_question`. This went red naming the screen. Restored from a
    # copy.
    test "no setup asks a boolean question" do
      for {name, _document, screens} <- paths(), screen <- screens["screens"] do
        refute Enum.any?(screen["nodes"], &(&1["type"] == "boolean_question")),
               "#{name}'s #{screen["key"]} asks a boolean question"
      end
    end
  end

  describe "each setup run alone as a durable Journey" do
    # Sabotage: emptied the catalogue sync's schedule step `responses`. The
    # schedule press recorded nothing and this went red on the collected
    # responses. Restored from a copy.
    test "walks its three steps, with Back after the first, and finishes done" do
      for {key, walk} <- @walks do
        {execution_id, opts} = start(key)

        final =
          walk
          |> Enum.with_index()
          |> Enum.reduce(nil, fn {{screen, outcome, press}, index}, _view ->
            {:ok, view} = Journey.current(execution_id, opts)
            assert screen_key(view) == screen, "#{key} is not on #{screen}"
            assert view.back == index > 0, "#{key}'s Back on #{screen}"

            {:ok, next} = Journey.submit(execution_id, outcome, press, opts)
            next
          end)

        assert final.state == "done", "#{key} did not finish"
        refute final.back

        expected = walk |> Enum.map(&elem(&1, 2)) |> Enum.reduce(%{}, &Map.merge(&2, &1))
        assert final.responses == expected
      end
    end

    # Sabotage: misspelled `Journey.back_event/0`. The back request raised an
    # event no step listens for, the execution stayed on the second step and
    # this went red. Reverted from a copy.
    test "goes back from the second step to the first, keeping what was given" do
      for {key, [{first, outcome, press}, {second, _outcome, _press} | _rest]} <- @walks do
        {execution_id, opts} = start(key)

        {:ok, at_second} = Journey.submit(execution_id, outcome, press, opts)
        assert screen_key(at_second) == second

        {:ok, back} =
          Journey.back(execution_id, %{"screen" => second, "back" => true}, opts)

        assert screen_key(back) == first, "#{key} did not go back to #{first}"
        refute back.back
        assert back.responses == press
      end
    end
  end

  # Every Path built from `myapp.step` this app ships, with its screens
  # document: the three setups and the patron registration steps.
  defp paths do
    setups =
      for key <- Setups.keys() do
        {:ok, document} = Setups.document(key)
        {:ok, screens} = Setups.screens(key)
        {key, document, screens}
      end

    setups ++
      [{RegistrationSteps.key(), RegistrationSteps.document(), RegistrationSteps.screens()}]
  end

  defp outcomes(screen),
    do: for(%{"type" => "button", "outcome" => outcome} <- screen["nodes"], do: outcome)

  defp questions(screen) do
    for %{"type" => type, "key" => key} <- screen["nodes"],
        String.ends_with?(type, "_question"),
        do: key
  end
end
