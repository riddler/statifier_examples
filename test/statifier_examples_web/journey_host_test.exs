defmodule StatifierExamplesWeb.JourneyHostTest do
  @moduledoc """
  `StatifierExamplesWeb.JourneyHost` called as `RiddlerLiveView.Journey`
  calls it: what each callback answers, the outcome check on a submit, and
  the re-present a page draws as the reader types.
  """

  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Riddler.Journey.Scope
  alias StatifierExamples.Library.RegistrationSteps
  alias StatifierExamples.PresentedAnswerCheck
  alias StatifierExamples.Repo
  alias StatifierExamples.Signup.Journey
  alias StatifierExamplesWeb.{JourneyAccess, JourneyHost}

  doctest JourneyHost

  @account %{"first_name" => "Ada", "email" => "ada@example.com"}

  setup do
    :ok = Sandbox.checkout(Repo)
    :ok
  end

  # A signup Journey on its plan screen, by the name the page gives it.
  defp on_plan do
    {:ok, execution_id} = Journey.start("host-#{System.unique_integer([:positive])}")
    {:ok, _plan} = Journey.submit(execution_id, "account_submitted", @account)

    JourneyHost.journey(nil, execution_id)
  end

  defp submit(outcome, responses),
    do: %{"screen" => "plan", "outcome" => outcome, "responses" => responses}

  defp keys(answer), do: Enum.map(answer["screen"]["elements"], & &1["key"])

  test "a name is the page key and the execution id, read back as they were put" do
    assert {:ok, nil, "e-1"} = JourneyHost.parse(JourneyHost.journey(nil, "e-1"))

    assert {:ok, "branch_onboarding", "e&1=2"} =
             JourneyHost.parse(JourneyHost.journey("branch_onboarding", "e&1=2"))

    assert :error = JourneyHost.parse("path=branch_onboarding")
    assert :error = JourneyHost.parse(:not_a_name)
  end

  test "present answers the fixed scope beside riddler's answer, and refuses what it does not have" do
    journey = on_plan()

    assert {:ok, scope, %{"state" => "screen", "screen" => %{"key" => "plan"}}} =
             JourneyHost.present(journey)

    assert scope == JourneyHost.scope()
    assert {:error, :no_such_journey} = JourneyHost.present(JourneyHost.journey(nil, "nobody"))

    assert {:error, :no_such_journey} =
             JourneyHost.present(JourneyHost.journey("no_such_path", "nobody"))
  end

  test "start starts a Journey under the fixed scope only" do
    assert {:ok, journey, %{"state" => "screen", "screen" => %{"key" => "account"}}} =
             JourneyHost.start("signup_path", JourneyHost.scope())

    assert {:ok, nil, _execution_id} = JourneyHost.parse(journey)

    {:ok, elsewhere} = Scope.new("branch", "elsewhere")
    assert {:error, :no_such_journey} = JourneyHost.start("signup_path", elsewhere)
    assert {:error, :no_such_journey} = JourneyHost.start("no_such_path", JourneyHost.scope())
  end

  test "the access module admits any actor to the signup Path's scope, and not to a branch" do
    {:ok, elsewhere} = Scope.new("branch", "elsewhere")

    assert :ok = Riddler.Journey.Access.check(JourneyAccess, nil, JourneyHost.scope(), :submit)

    assert {:error, :no_such_journey} =
             Riddler.Journey.Access.check(JourneyAccess, "anyone", elsewhere, :present)

    assert JourneyAccess.scopes("anyone") == [JourneyHost.scope()]
  end

  # THE OUTCOME CHECK. The plan button is revealed by the seat count typed
  # on the plan screen itself, so the check has to resolve the screen with
  # the submitted responses laid over what the chart holds.
  #
  # Sabotage (run): made `Signup.Journey.submit/4` look for the pressed
  # button among the screen resolved with what the chart holds alone, the
  # submitted responses dropped. The press with the revealing seat count
  # was refused as an unknown outcome and this went red on the accepted
  # press. Restored from a copy.
  test "a revealed plan button is accepted with responses that reveal it, and refused without" do
    journey = on_plan()

    assert {:error, []} = JourneyHost.submit(journey, submit("personal_chosen", %{}))
    assert_received {JourneyHost, {:error, {:unknown_outcome, "personal_chosen"}}}

    assert {:error, []} =
             JourneyHost.submit(journey, submit("personal_chosen", %{"seats" => "5"}))

    assert_received {JourneyHost, {:error, {:unknown_outcome, "personal_chosen"}}}

    assert {:ok, %{"state" => "screen", "screen" => %{"key" => "confirm"}}} =
             JourneyHost.submit(journey, submit("personal_chosen", %{"seats" => "1"}))

    assert_received {JourneyHost, {:view, %{state: "screen", screen: %{key: "confirm"}}}}
  end

  # Sabotage (run): made `Validation.check/2` leave each finding's
  # `author_message` as riddler gave it. The findings carried none and this
  # went red on the list. Restored from a copy.
  test "a submit the screen refuses answers riddler's findings in this app's words" do
    journey = JourneyHost.journey(nil, elem(Journey.start("host-#{System.unique_integer()}"), 1))

    assert {:error, findings} =
             JourneyHost.submit(journey, %{
               "screen" => "account",
               "outcome" => "account_submitted",
               "responses" => %{"email" => "ada"}
             })

    assert [
             {"response.required", "first_name", "is required"},
             {"response.format", "email", "must look like an email address"}
           ] == Enum.map(findings, &{&1.code, &1.element_key, &1.author_message})

    assert_received {JourneyHost, {:view, %{findings: [_, _]}}}
  end

  # The re-present is a presented answer, so it is checked as every answer
  # a view is drawn from is.
  #
  # Sabotage (run): removed the `check_presented/1` call from
  # `Signup.Journey.present_draft/3`. The re-presented answer was not
  # recorded and this went red on the last assertion. Restored from a copy.
  test "a re-present draws the plan button the draft reveals, and the answer is checked" do
    journey = on_plan()

    assert {:ok, answer} =
             JourneyHost.re_present(journey, %{
               "screen" => "plan",
               "responses" => %{"seats" => "1"}
             })

    assert "plan_personal" in keys(answer)
    refute "plan_business" in keys(answer)
    assert "personal_chosen" in answer["moves"]["outcomes"]
    assert hd(PresentedAnswerCheck.answers()) == answer

    assert {:error, :no_such_journey} =
             JourneyHost.re_present(JourneyHost.journey(nil, "nobody"), %{"responses" => %{}})
  end

  test "back steps the registration steps back, and refuses a request the moves do not offer" do
    opts = RegistrationSteps.options()
    {:ok, execution_id} = Journey.start("host-steps-#{System.unique_integer([:positive])}", opts)
    journey = JourneyHost.journey("patron_registration_steps", execution_id)

    assert {:error, []} =
             JourneyHost.back(journey, %{"screen" => "patron_name", "back" => true})

    {:ok, _card} =
      Journey.submit(
        execution_id,
        "name_given",
        %{"first_name" => "Rosa", "email" => "rosa@example.com"},
        opts
      )

    assert {:ok, %{"screen" => %{"key" => "patron_name"}}} =
             JourneyHost.back(journey, %{"screen" => "patron_card", "back" => true})
  end
end
