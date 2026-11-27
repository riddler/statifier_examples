defmodule StatifierExamples.Signup.SealedSecretTest do
  @moduledoc """
  The patron registration screens ask a new patron for the PIN of their
  library card, a secret question, and the Journey that runs them seals the
  response before the chart sees it: validated as typed, sealed through
  `Riddler.Screens.seal_secrets/4` with the app's sealer, and only then sent.

  The PIN in these tests is a sentinel string, so a search for it anywhere -
  a stored row, a presented answer, a log line - finds only a leak.

  The stored-row search is the proof for a stored blob, and the log search
  is not: Ecto's debug query log cuts each binary parameter short after
  about 50 bytes, so a captured log line can lack the bytes a plaintext
  secret would occupy. An empty search of the log alone therefore proves
  nothing about what was written.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Ecto.Adapters.SQL.Sandbox
  alias StatifierBlocks.Document
  alias StatifierExamples.PresentedAnswerCheck
  alias StatifierExamples.Repo
  alias StatifierExamples.ScreenEditor.Try
  alias StatifierExamples.Signup.Journey
  alias StatifierExamples.Signup.Sealer
  alias StatifierExamples.TestSealer

  @registration "priv/fixtures/patron_registration_screens.json"

  @sentinel "SENTINEL-PIN-not-a-real-pin"

  @details %{
    "first_name" => "Rosa",
    "email" => "rosa@example.com",
    "age" => "34",
    "library_pin" => @sentinel
  }

  @card %{"card_type" => "standard", "interests" => [], "lending_rules" => true}

  defmodule FailingSealer do
    @moduledoc false
    def seal(_plaintext), do: {:error, :key_unavailable}
  end

  setup do
    :ok = Sandbox.checkout(Repo)
  end

  describe "a PIN submitted on the patron registration screens" do
    # Sabotage: made Journey.submit/4 send the responses unsealed (skip the
    # seal); the sentinel was found in a stored row, then reverted.
    test "occurs in no stored row, no presented answer and no log line" do
      level = Logger.level()
      Logger.configure(level: :debug)
      on_exit(fn -> Logger.configure(level: level) end)

      {views, log} =
        with_log([level: :debug], fn ->
          {id, opts} = start()
          {:ok, details} = Journey.current(id, opts)

          {:invalid, refused} =
            Journey.submit(id, "details_submitted", %{@details | "email" => "rosa"}, opts)

          {:ok, card} = Journey.submit(id, "details_submitted", @details, opts)
          {:ok, done} = Journey.submit(id, "registration_submitted", @card, opts)

          [details, refused, card, done]
        end)

      Logger.configure(level: level)

      stored = stored_values()
      refute Enum.any?(stored, &String.contains?(&1, @sentinel))
      # The log search below cannot stand alone for stored blobs: the query
      # log truncates binary parameters, so the stored-row search above is
      # the proof that no row holds the PIN.
      refute log =~ @sentinel
      for view <- views, do: refute(inspect(view) =~ @sentinel)

      answers = PresentedAnswerCheck.answers()
      for answer <- answers, do: refute(inspect(answer) =~ @sentinel)

      # Each search reads where the PIN would land: the sealed string is in
      # a stored row and the run logged its queries, so an empty search is
      # not a search of nothing.
      assert Enum.any?(stored, &String.contains?(&1, TestSealer.sealed(@sentinel)))
      assert log =~ "QUERY OK"
      assert length(answers) >= length(views)

      assert [_details, %{findings: [{"email", _message}]}, %{state: "screen"}, done] = views
      assert done.responses["library_pin"] == %{"sealed" => TestSealer.sealed(@sentinel)}
    end

    # Sabotage: moved the seal after coerce/1; the PIN became an integer
    # and riddler refused it as response.invalid_shape, then reverted.
    test "is sealed as text when it is digits alone" do
      {id, opts} = start()
      pin = "4719"

      assert {:ok, _card} =
               Journey.submit(id, "details_submitted", %{@details | "library_pin" => pin}, opts)

      {:ok, done} = Journey.submit(id, "registration_submitted", @card, opts)

      assert done.responses["library_pin"] == %{"sealed" => TestSealer.sealed(pin)}
    end

    test "left blank is refused by the check and nothing is sent" do
      {id, opts} = start()

      assert {:invalid, refused} =
               Journey.submit(id, "details_submitted", %{@details | "library_pin" => ""}, opts)

      assert refused.findings == [{"library_pin", "is required"}]
      assert {:ok, %{screen: %{key: "patron_details"}}} = Journey.current(id, opts)
    end

    # Sabotage: made the secret question present its typed response through
    # resolve/2 (the drop removed); the draft view carried the sentinel,
    # then reverted.
    test "typed and not sent stays out of the view a page draws" do
      {id, opts} = start()
      {:ok, details} = Journey.current(id, opts)

      drafted = Journey.resolve(details, @details)

      assert drafted.responses["first_name"] == "Rosa"
      refute Map.has_key?(drafted.responses, "library_pin")
      assert %{"held" => false} = Enum.find(drafted.nodes, &(&1["key"] == "library_pin"))
      refute inspect(drafted) =~ @sentinel
    end
  end

  describe "a sealer that does not seal" do
    setup do
      put_sealer(FailingSealer)
    end

    # Sabotage: made Journey.submit/4 send the responses unsealed; the press
    # went through, then reverted.
    test "refuses the press and sends nothing" do
      {id, opts} = start()

      assert {:error, {:seal_secrets, [finding]}} =
               Journey.submit(id, "details_submitted", @details, opts)

      assert {finding.code, finding.element_key} == {"response.seal_failed", "library_pin"}
      assert {:ok, %{screen: %{key: "patron_details"}}} = Journey.current(id, opts)
    end
  end

  describe "the app's sealer, with no sealer configured" do
    setup do
      put_sealer(nil)
    end

    # Sabotage: made the endpoint sealer answer the text unencrypted; the
    # sealed string was the text itself, then reverted.
    test "encrypts with Plug.Crypto under the endpoint secret" do
      assert {:ok, sealed} = Sealer.seal(@sentinel)

      refute sealed =~ @sentinel

      secret = StatifierExamplesWeb.Endpoint.config(:secret_key_base)

      assert {:ok, @sentinel} =
               Plug.Crypto.decrypt(secret, "library card secret", sealed, max_age: :infinity)
    end
  end

  defp put_sealer(sealer) do
    previous = Application.get_env(:statifier_examples, Sealer)
    Application.put_env(:statifier_examples, Sealer, sealer: sealer)
    on_exit(fn -> Application.put_env(:statifier_examples, Sealer, previous) end)
  end

  # A Journey over the patron registration screens as authored, started the
  # way the screen editor's Try action starts one.
  defp start do
    {:ok, document} = @registration |> File.read!() |> Document.from_json()
    {:ok, %{execution_id: id, opts: opts}} = Try.start(document)
    {id, opts}
  end

  # Every value of every row of every table the test's sandbox can read, as
  # the bytes stored: a term stored as a binary is searched as its bytes, so
  # a string inside it is found as written.
  defp stored_values do
    {:ok, %{rows: tables}} =
      Repo.query("SELECT name FROM sqlite_master WHERE type = 'table'", [])

    for [table] <- tables,
        {:ok, %{rows: rows}} = Repo.query(~s(SELECT * FROM "#{table}"), []),
        row <- rows,
        value <- row,
        is_binary(value),
        do: value
  end
end
