defmodule StatifierExamples.Signup.RiddlerTest do
  @moduledoc """
  What this app hands to riddler: resolving a screen, checking a screen's
  responses, and presenting a Journey's step, and the screens document a
  caller may supply in place of the fixture.

  Every document written here is patron registration: a visitor getting a
  library card. The supplied document keeps the screen keys and the button
  outcomes of the Path fixture, because the chart is that fixture's and
  those are what it parks on and listens for.

  Not async: the Journey cases step durable executions through the
  application's named `StatifierExamples.Charts.ExecutionLock`.
  """

  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias StatifierExamples.Charts.{AsyncCalls, Durable}
  alias StatifierExamples.Repo
  alias StatifierExamples.Signup.{Journey, Screens, Validation}

  @patron %{"first_name" => "Ada", "email" => "ada@example.com"}

  # A library card's screens, on the Path's three screen keys.
  @library_card %{
    "schema_version" => 1,
    "id" => "edoc_library_card",
    "screens" => [
      %{
        "key" => "account",
        "title" => "Get your library card",
        "nodes" => [
          %{
            "type" => "heading",
            "key" => "card_heading",
            "level" => 1,
            "text" => "Get your library card"
          },
          %{
            "type" => "text_question",
            "key" => "first_name",
            "label" => "First name",
            "required" => true
          },
          %{
            "type" => "text_question",
            "key" => "email",
            "label" => "Email for hold notices",
            "required" => true,
            "format" => "email"
          },
          %{
            "type" => "button",
            "key" => "card_next",
            "label" => "Next",
            "outcome" => "account_submitted"
          }
        ]
      },
      %{
        "key" => "plan",
        "title" => "Choose your card",
        "nodes" => [
          %{
            "type" => "text",
            "key" => "card_choice",
            "text" => "Welcome, {{ responses.first_name | upcase }}."
          },
          %{
            "type" => "button",
            "key" => "card_standard",
            "label" => "A standard card",
            "outcome" => "personal_chosen"
          },
          %{"type" => "button", "key" => "card_back", "label" => "Back", "outcome" => "went_back"}
        ]
      },
      %{
        "key" => "confirm",
        "title" => "Pick up your card",
        "nodes" => [
          %{
            "type" => "text",
            "key" => "card_pickup",
            "text" => "We will email {{ responses.email }} when your card is at the front desk."
          },
          %{
            "type" => "button",
            "key" => "card_issue",
            "label" => "Issue my card",
            "outcome" => "signup_confirmed"
          }
        ]
      }
    ]
  }

  defp key(%{screen: nil}), do: nil
  defp key(%{screen: screen}), do: screen.key

  defp keys(%{nodes: nodes}), do: Enum.map(nodes, & &1["key"])

  describe "the fixture as riddler reads it" do
    test "signup_screens.json is admitted with zero findings" do
      assert {:ok, %Riddler.Screens.Document{}} = Screens.admit(Screens.document())
    end

    test "a document riddler does not admit is refused, and says why" do
      assert Screens.admit(%{"screens" => "three of them"}) ==
               {:error, :not_a_screens_document}

      assert {:error, [%Riddler.Finding{code: "document.unknown_type"}]} =
               Screens.admit(%{
                 "schema_version" => 1,
                 "id" => "edoc_library_card",
                 "screens" => [
                   %{
                     "key" => "account",
                     "title" => "Get your library card",
                     "nodes" => [%{"type" => "barcode_scanner", "key" => "card_scan"}]
                   }
                 ]
               })
    end
  end

  describe "the screen is resolved by riddler" do
    # Sabotage (run): replaced `Screens.resolve/2`'s body with the regex
    # stand-in it retired - every node kept whose `condition` predicator
    # answers true, then `fill_slots/2` over `text`. Two cases went red on
    # an assertion: this one, because the regex has no filter and the text
    # kept its raw `{{ ... | upcase }}`, and the next, because the kept node
    # still carried its `condition`. Reverted from a copy.
    test "a template filter is rendered, which only riddler's subset does" do
      screen = Screens.screen(@library_card, "plan")
      nodes = Screens.resolve(screen, %{"responses" => %{"first_name" => "Ada"}})

      assert Enum.find(nodes, &(&1["key"] == "card_choice"))["text"] == "Welcome, ADA."
    end

    test "a resolved node is string-keyed and carries no condition" do
      screen = %{
        key: "account",
        title: "Get your library card",
        nodes: [
          %{
            "type" => "text",
            "key" => "card_returning",
            "condition" => "responses.returning == true",
            "text" => "Welcome back."
          }
        ]
      }

      assert Screens.resolve(screen, %{"responses" => %{"returning" => true}}) == [
               %{"type" => "text", "key" => "card_returning", "text" => "Welcome back."}
             ]

      assert Screens.resolve(screen, %{"responses" => %{}}) == []
    end
  end

  describe "the responses are checked by riddler" do
    # Sabotage (run): made `Validation.validate/2` answer `[]` for every node
    # that is not a `text_question`, as the stand-in did. This case went red:
    # the choice question's refused value came back with no finding.
    # Reverted from a copy.
    test "a choice question's value no option carries is refused" do
      nodes = [
        %{
          "type" => "choice_question",
          "key" => "card_kind",
          "label" => "Which card?",
          "select" => "one",
          "required" => true,
          "answer_options" => [
            %{"value" => "standard", "label" => "Standard"},
            %{"value" => "junior", "label" => "Junior"}
          ]
        }
      ]

      assert [{"card_kind", message}] = Validation.validate(nodes, %{"card_kind" => "gold"})
      assert is_binary(message)
      assert Validation.validate(nodes, %{"card_kind" => "junior"}) == []
      assert Validation.validate(nodes, %{}) == [{"card_kind", "is required"}]
    end
  end

  describe "the Journey's step is riddler's answer" do
    setup do
      :ok = Sandbox.checkout(Repo)
      %{execution_id: "riddler-#{System.unique_integer([:positive])}"}
    end

    # Sabotage (run): made `journey_status/2` answer `:waiting` for an
    # execution that has stopped running. This case went red on its last
    # `state`, which read "waiting" for the finished execution, and so did
    # the supplied-document run below, on the same assertion. Reverted from
    # a copy.
    test "a screen, waiting on the asynchronous call, and done", %{execution_id: execution_id} do
      {:ok, ^execution_id} = Journey.start(execution_id)

      {:ok, account} = Journey.current(execution_id)
      assert account.state == "screen"

      {:ok, _plan} = Journey.submit(execution_id, "account_submitted", @patron)
      {:ok, mid_call} = Journey.submit(execution_id, "business_chosen", %{"seats" => "5"})
      assert key(mid_call) == nil
      assert mid_call.state == "waiting"
      assert mid_call.nodes == []

      assert %{success: 1} = Oban.drain_queue(queue: AsyncCalls.queue())

      {:ok, done} = Journey.submit(execution_id, "signup_confirmed", %{})
      assert done.status == :done
      assert done.state == "done"
    end
  end

  describe "a screens document the caller supplies" do
    setup do
      :ok = Sandbox.checkout(Repo)
      %{execution_id: "library-card-#{System.unique_integer([:positive])}"}
    end

    # Sabotage (run): made `screens_document/1` ignore `opts[:screens]` and
    # read the fixture. This case went red on the first screen's title,
    # which read the fixture's, and so did both refusal cases below, whose
    # starts succeeded. Reverted from a copy.
    test "the Journey draws the supplied screens and runs to done", %{
      execution_id: execution_id
    } do
      opts = [screens: @library_card]

      assert {:ok, ^execution_id} = Journey.start(execution_id, opts)

      {:ok, account} = Journey.current(execution_id, opts)
      assert account.screen.title == "Get your library card"
      assert keys(account) == ["card_heading", "first_name", "email", "card_next"]

      assert {:invalid, refused} =
               Journey.submit(execution_id, "account_submitted", %{"first_name" => "Ada"}, opts)

      assert refused.findings == [{"email", "is required"}]

      {:ok, plan} = Journey.submit(execution_id, "account_submitted", @patron, opts)
      assert key(plan) == "plan"
      assert Enum.find(plan.nodes, &(&1["key"] == "card_choice"))["text"] == "Welcome, ADA."

      {:ok, confirm} = Journey.submit(execution_id, "personal_chosen", %{}, opts)

      assert Enum.find(confirm.nodes, &(&1["key"] == "card_pickup"))["text"] ==
               "We will email ada@example.com when your card is at the front desk."

      {:ok, done} = Journey.submit(execution_id, "signup_confirmed", %{}, opts)
      assert done.state == "done"
    end

    # Sabotage (run): put the parked-screen clause of `journey_status/2`
    # back ahead of the status check, so a parked key wins whatever the
    # execution's status. This case went red on an assertion: the abandoned
    # execution's `state` read "screen". Reverted from a copy.
    test "a card request abandoned on a screen is done, with nothing to fill in", %{
      execution_id: execution_id
    } do
      opts = [screens: @library_card]
      {:ok, ^execution_id} = Journey.start(execution_id, opts)
      {:ok, plan} = Journey.submit(execution_id, "account_submitted", @patron, opts)
      assert plan.state == "screen"

      {:ok, {{durable, _run}, _document}} = Durable.resume(execution_id)
      assert :ok = Durable.abandon(durable)

      {:ok, stopped} = Journey.current(execution_id, opts)
      assert key(stopped) == "plan"
      assert stopped.status == :failed
      assert stopped.state == "done"
      assert stopped.nodes == []

      {:ok, refused} = Journey.submit(execution_id, "personal_chosen", %{}, opts)
      assert refused.discarded == :failed
      assert refused.state == "done"
      assert refused.nodes == []
    end

    test "a document riddler does not admit starts nothing", %{execution_id: execution_id} do
      assert {:error, {:screens_document, :not_a_screens_document}} =
               Journey.start(execution_id, screens: %{"screens" => "three of them"})

      assert {:error, :execution_not_found} = Journey.current(execution_id)
    end

    # Sabotage (run): made `declares_path_screens/2` answer `:ok` whatever
    # the document declares. This case went red: the start succeeded.
    # Reverted from a copy.
    test "a document missing a screen the Path names starts nothing", %{
      execution_id: execution_id
    } do
      partial =
        Map.update!(@library_card, "screens", &Enum.reject(&1, fn s -> s["key"] == "confirm" end))

      assert Journey.start(execution_id, screens: partial) ==
               {:error, {:undeclared_screens, ["confirm"]}}

      assert {:error, :execution_not_found} = Journey.current(execution_id)
    end
  end
end
