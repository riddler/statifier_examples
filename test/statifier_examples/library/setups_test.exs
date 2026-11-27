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

  doctest StatifierExamples.Library.Setup

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
    #
    # Sabotage: made `myapp.setup`'s `declared_outcomes/1` answer `done`
    # alone. The card-reader setup declared one outcome and this went red.
    # Restored from a copy.
    test "each document declares its root outcomes, compiled for use as a child" do
      assert Setups.outcomes("catalogue_sync") == {:ok, ["done"]}
      assert Setups.outcomes("reading_list_import") == {:ok, ["done"]}
      assert Setups.outcomes("card_reader_setup") == {:ok, ["done", "site_visit_needed"]}
    end

    # Pins the sentence's register; that the page draws it is
    # `StatifierExamplesWeb.SettingsLiveTest`'s.
    #
    # Sabotage: named the catalogue sync's file in its sentence. This went
    # red on the file refute. Restored from a copy.
    test "each setup has a sentence for a librarian, and no block type or file in it" do
      for key <- Setups.keys() do
        assert {:ok, description} = Setups.description(key)
        assert description != ""
        refute description =~ "myapp."
        refute description =~ ".json"
      end

      assert Setups.description("branch_closure") == :error
    end
  end

  describe "each step's config agrees with the screen it names" do
    # Sabotage: changed `"buttons": ["schedule_chosen"]` on the catalogue
    # sync's schedule step to `["schedule_given"]`. This went red naming
    # the block. Restored from a copy.
    test "its buttons are the screen's buttons and its responses the screen's questions" do
      for {name, %Document{} = document, screens} <- paths() do
        steps = for %Block{type: "myapp.step"} = block <- Document.blocks(document), do: block
        assert steps != [], "#{name} has no myapp.step block"

        for %Block{id: id, config: config} <- steps do
          screen = Enum.find(screens["screens"], &(&1["key"] == config["screen"]))
          assert screen, "#{name} #{id} names a screen its screens document does not declare"

          assert Enum.sort(config["buttons"]) == screen |> outcomes() |> Enum.sort(),
                 "#{name} #{id}'s buttons are not its screen's buttons"

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
        refute Enum.any?(screen["elements"], &(&1["type"] == "boolean_question")),
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

    # The card-reader setup's ending is on its last screen, so this walks a
    # test-only copy whose ending is on the first: a press that ends the
    # setup leaves the steps after it unvisited.
    #
    # Sabotage: made the ending's handler drop its `ending_when` condition.
    # The desk reader's press ended the setup too and this went red on its
    # screen. Restored from a copy.
    test "a press its root names as an ending ends it, with the steps after it unvisited" do
      {:ok, [screens: screens, path: %Document{root: root} = path]} =
        Setups.options("card_reader_setup")

      config = %{
        "ending" => "no_reader_yet",
        "ending_on" => "model_chosen",
        "ending_when" => "_event.data.reader_kind == 'self_checkout'"
      }

      opts = [screens: screens, path: %Document{path | root: %{root | config: config}}]

      for {kind, expected} <- [{"self_checkout", nil}, {"desk_reader", "reader_place"}] do
        {:ok, id} = Journey.start("setup-ending-#{System.unique_integer([:positive])}", opts)
        {:ok, view} = Journey.submit(id, "model_chosen", %{"reader_kind" => kind}, opts)

        assert screen_key(view) == expected, "#{kind} did not rest on #{inspect(expected)}"
        assert view.responses == %{"reader_kind" => kind}
        assert view.state == "done" == is_nil(expected)
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
    do: for(%{"type" => "button", "outcome" => outcome} <- screen["elements"], do: outcome)

  defp questions(screen) do
    for %{"type" => type, "key" => key} <- screen["elements"],
        String.ends_with?(type, "_question"),
        do: key
  end
end
