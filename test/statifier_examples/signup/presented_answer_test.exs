defmodule StatifierExamples.Signup.PresentedAnswerTest do
  @moduledoc """
  Every answer `Riddler.Journey.present/3` gives the signup Journey keeps to
  the presented answer schema riddler ships.

  The check itself runs inside `StatifierExamples.Signup.Journey`, on every
  answer a view is drawn from, through the `:presented_answer_check`
  `config/test.exs` names (`StatifierExamples.PresentedAnswerCheck`). So
  the Journey tests and the page tests check every answer they draw without
  a line of their own. This module proves the three things that makes
  true: the check is wired, it reads the schema out of the riddler
  dependency rather than a copy, and it refuses an answer that does not
  keep to the schema. It also drives one Journey through all three states,
  so the check is seen admitting a screen, a waiting and a done answer.
  """

  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias StatifierExamples.Charts.AsyncCalls
  alias StatifierExamples.PresentedAnswerCheck
  alias StatifierExamples.Repo
  alias StatifierExamples.Signup.{Journey, Screens}

  @account %{"first_name" => "Ada", "email" => "ada@example.com"}

  setup do
    :ok = Sandbox.checkout(Repo)
    :ok
  end

  # A real screen answer for the fixture's first screen, straight from riddler.
  defp screen_answer do
    {:ok, admitted} = Screens.admit(Screens.document())
    {:ok, answer} = Riddler.Journey.present(admitted, {:screen, "account"}, %{})
    answer
  end

  # Sabotage (run): set `:presented_answer_check` to `nil` in
  # `config/test.exs`; this went red here and on the `checked/0`
  # assertion below. Restored from a copy.
  test "the Journey names the check in the test environment" do
    assert Application.fetch_env!(:statifier_examples, Journey)[:presented_answer_check] ==
             PresentedAnswerCheck
  end

  # Sabotage (run): pointed `schema_path/0` at the same file through the
  # app's own `deps/riddler` directory rather than the riddler
  # application's; this went red on the path assertion. Restored from a
  # copy.
  test "the schema is read from the riddler dependency, and the app carries no copy" do
    path = PresentedAnswerCheck.schema_path()

    assert path ==
             Path.join(Application.app_dir(:riddler), "priv/schemas/presented-answer.schema.json")

    assert File.regular?(path)

    copies =
      ["lib", "test", "priv", "config", "assets"]
      |> Enum.flat_map(&Path.wildcard(Path.join(&1, "**/presented-answer.schema.json")))

    assert copies == []
  end

  # Sabotage (run): made `check!/1` answer `:ok` without validating; this
  # went red on the first `assert_raise`. Restored from a copy.
  test "an answer that does not keep to the schema is refused" do
    answer = screen_answer()
    assert :ok = PresentedAnswerCheck.check!(answer)

    # A screen answer with no moves, a node with no key, and a state
    # riddler never answers.
    no_moves = Map.delete(answer, "moves")
    [first | rest] = answer["screen"]["nodes"]
    keyless = put_in(answer, ["screen", "nodes"], [Map.delete(first, "key") | rest])
    elsewhere = %{"state" => "elsewhere"}

    for broken <- [no_moves, keyless, elsewhere] do
      assert {:error, [_ | _]} = PresentedAnswerCheck.validate(broken)

      assert_raise ExUnit.AssertionError, ~r/presented-answer\.schema\.json/, fn ->
        PresentedAnswerCheck.check!(broken)
      end
    end
  end

  # Sabotage (run): removed the `check_presented/1` call from the
  # Journey's `view/5`; this went red on the first `checked/0` assertion.
  # Restored from a copy.
  #
  # Sabotage (run), against the dependency: renamed the `"moves"` key of
  # the screen answer `Riddler.Journey.present/3` builds in
  # `deps/riddler` and recompiled riddler for the test environment. The
  # existing Journey, riddler, Try and page tests went red on the check's
  # assertion (the page tests through the LiveView's exit carrying it),
  # with no line of theirs changed. Restored from a copy and recompiled.
  test "a Journey through screen, waiting and done has every answer checked" do
    Process.delete({PresentedAnswerCheck, :checked})
    {:ok, execution_id} = Journey.start("presented-#{System.unique_integer([:positive])}")

    {:ok, account} = Journey.current(execution_id)
    assert account.state == "screen"
    assert PresentedAnswerCheck.checked() == ["screen"]

    {:ok, _plan} = Journey.submit(execution_id, "account_submitted", @account)
    {:ok, mid_call} = Journey.submit(execution_id, "business_chosen", %{"seats" => "5"})
    assert mid_call.state == "waiting"

    assert %{success: 1} = Oban.drain_queue(queue: AsyncCalls.queue())

    {:ok, done} = Journey.submit(execution_id, "signup_confirmed", %{"referral" => "A colleague"})
    assert done.state == "done"

    checked = PresentedAnswerCheck.checked()
    assert hd(checked) == "done"
    assert "waiting" in checked
    assert Enum.uniq(checked) |> Enum.sort() == ["done", "screen", "waiting"]
  end
end
