defmodule StatifierExamplesWeb.EventPhrasingTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.Block
  alias StatifierBlocks.Document
  alias StatifierBlocks.ViewModel
  alias StatifierExamples.Charts
  alias StatifierExamplesWeb.EventPhrasing

  @library ["library_loan", "patron_registration"]

  describe "phrase/1" do
    test "reads a library event name as what happened" do
      assert EventPhrasing.phrase("copy.returned") == "the copy is returned"
      assert EventPhrasing.phrase("guardian.consented") == "a guardian consents"
    end

    test "answers nil for an event name it has no words for" do
      assert EventPhrasing.phrase("payment.settled") == nil
      assert EventPhrasing.phrase(nil) == nil
    end

    # Every event the two teaching documents send, wait for, listen for or
    # accept has its words, so neither document draws a bare event name in
    # a sentence.
    #
    # Sabotage: dropped "card.ready" from the table; this went red.
    # Reverted from a copy.
    test "has words for every event the two library documents name" do
      for key <- @library do
        {:ok, fixture} = Charts.fixture(key)

        for event <- events(fixture.document) do
          assert is_binary(EventPhrasing.phrase(event)), "#{key}: no words for #{event}"
        end
      end
    end
  end

  describe "line/1" do
    # Sabotage: made the send rule answer the bare clause without "word
    # that"; this went red. Reverted from a copy.
    test "a send says what it announces" do
      assert EventPhrasing.line("Send loan.closed") == "Send word that the loan is closed"
    end

    # Sabotage: dropped the wait rule, leaving the plain substitution; this
    # went red. Reverted from a copy.
    test "a wait says what it waits until, keeping its timeout" do
      assert EventPhrasing.line("Wait for guardian.consented, giving up after 14d") ==
               "Wait until a guardian consents, giving up after 14d"

      assert EventPhrasing.line("Wait for email.verified") ==
               "Wait until the email address is verified"
    end

    test "a rule's event reads as a clause" do
      assert EventPhrasing.line("When registration.deadline, abandon") ==
               "When the registration week is up, abandon"
    end

    test "every event in a line is phrased, and nothing else changes" do
      assert EventPhrasing.line(
               "After Send loan.overdue, Wait for copy.returned, giving up after 14d"
             ) ==
               "After Send word that the loan is overdue, " <>
                 "Wait until the copy is returned, giving up after 14d"
    end

    # A name that only starts or ends like a known one is a different event.
    #
    # Sabotage: dropped the lookbehind and lookahead from the match; this
    # went red. Reverted from a copy.
    test "matches a whole event name only" do
      assert EventPhrasing.line("Send loan.closed_early") == "Send loan.closed_early"
      assert EventPhrasing.line("Send old.loan.closed") == "Send old.loan.closed"
    end

    test "leaves a line with no known event name as it is" do
      assert EventPhrasing.line("Send payment.settled") == "Send payment.settled"
      assert EventPhrasing.line("Wait 21d") == "Wait 21d"
    end
  end

  describe "sentence/1" do
    test "is the block's sentence, its event name phrased" do
      root =
        Block.new("core.sequence",
          id: "root",
          slots: %{
            "body" => [
              Block.new("core.send", id: "closed", config: %{"event" => "loan.closed"}),
              Block.new("core.wait", id: "wait", config: %{"duration" => "30s"})
            ]
          }
        )

      view_model = root |> Document.new() |> ViewModel.build(Charts.palette(), [])

      assert view_model |> ViewModel.find_node("closed") |> EventPhrasing.sentence() ==
               "Send word that the loan is closed"

      assert view_model |> ViewModel.find_node("wait") |> EventPhrasing.sentence() == "Wait 30s"
    end
  end

  # Every "event" config value in the document, and every event it accepts.
  defp events(%Document{root: root, accepts: accepts}),
    do: Enum.uniq((accepts || []) ++ block_events(root))

  defp block_events(%Block{config: config, slots: slots}) do
    own =
      case config do
        %{"event" => event} when is_binary(event) -> [event]
        _other -> []
      end

    own ++
      Enum.flat_map(slots, fn {_name, children} -> Enum.flat_map(children, &block_events/1) end)
  end
end
