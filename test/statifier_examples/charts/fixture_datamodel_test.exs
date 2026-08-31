defmodule StatifierExamples.Charts.FixtureDatamodelTest do
  @moduledoc """
  The shipped fixtures declare the `<data>` roots their own expressions
  read, in their own bytes.

  sb ADR-0001 decision 11 gives a block document a top-level `datamodel`
  key, and this app is the reference embedder for it. The property worth
  asserting is not that the key is present - it is that the key is
  *complete*: a root an emitted expression loads and nothing declares is
  an `error.execution` at run time, which is exactly the defect that used
  to send every run of the wizard down its `otherwise` arm.

  So the check is derived rather than transcribed. Each fixture is
  compiled, every `cond`, `expr` and `location` attribute in the generated
  SCXML is put through `Predicator.compile/1`, and the roots its `load`
  instructions name are compared against the `<data>` ids the same chart
  declares. Nothing here lists which roots a chart reads; the chart is
  asked.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.Compiler
  alias StatifierBlocks.Palette
  alias StatifierExamples.Charts
  alias StatifierExamples.Charts.Durable
  alias StatifierExamples.Test.LegacyCheck

  # The one root an expression may load without any `<data>` declaring it:
  # the engine puts the current event there itself.
  @engine_roots ["_event"]

  # Sabotage: dropped the `"review"` entry from `card_processing.json`'s
  # `datamodel` key; this went red naming `review`, which the park step's
  # `<assign location="review.parked">` loads. Reverted.
  test "every root a compiled fixture loads is declared as a <data> root" do
    for fixture <- Charts.fixtures() do
      scxml = compile!(fixture)
      declared = data_ids(scxml)
      loaded = loaded_roots(scxml)

      # A fixture that loaded nothing would pass vacuously.
      assert loaded != [], "#{fixture.key} loads no roots at all"

      undeclared = loaded -- (declared ++ @engine_roots)

      assert undeclared == [],
             "#{fixture.key} reads #{inspect(undeclared)}, which nothing declares"
    end
  end

  # The ids themselves, so a fixture cannot quietly declare a root no
  # expression reads and stay green on the derived check above. The lists
  # are the emission order of each document's `datamodel` key.
  #
  # `three_ds` is the one entry the derived check does not cover: the
  # challenge lane's interrupt guard names `three_ds.completed`, but
  # `core.on_event` has no `cond` in its schema at the pinned editor, so
  # the compiler emits nothing that loads it yet. It is declared because
  # the document's own guard names it.
  #
  # Sabotage: appended `{"id": "unread"}` to `signup_wizard.json`'s
  # `datamodel`; this went red on the wizard's list. Reverted.
  test "each fixture declares its roots in its own bytes" do
    assert declared_ids("signup_wizard") == ["signup"]
    assert declared_ids("signup_invitations") == ["signup", "onboarding"]

    assert declared_ids("card_processing") == [
             "amount_cents",
             "currency",
             "customer",
             "card",
             "validation",
             "risk_rating",
             "fraud",
             "three_ds",
             "auth",
             "balance",
             "capture_attempts",
             "limits",
             "review"
           ]
  end

  # The other half of decision 11: the deployment's own list. This app adds
  # nothing to any document, which is what makes the fixtures portable -
  # a host that ships them declares nothing to run them.
  #
  # Sabotage: put `[{"signup", nil}]` back on the wizard's `@documents`
  # entry; this went red, and the compile in the first test then carried a
  # `:shadowed_document_root` warning. Reverted.
  test "the deployment adds no roots of its own" do
    for fixture <- Charts.fixtures() do
      assert fixture.declare == [], "#{fixture.key} host-declares #{inspect(fixture.declare)}"
    end
  end

  # Decision 11f's order, observed rather than described: the document's
  # roots reach the emitted `<datamodel>` ahead of any root a block
  # declares for itself. `signup_invitations` is the fixture that has both
  # - its `core.foreach` declares the loop's item and cursor.
  #
  # Sabotage: reversed the `datamodel` list in `signup_invitations.json`;
  # this went red on the head of the list. Reverted.
  test "document-declared roots lead the emitted datamodel" do
    {:ok, fixture} = Charts.fixture("signup_invitations")
    ids = fixture |> compile!() |> data_ids()

    assert ["signup", "onboarding" | block_declared] = ids
    assert block_declared != []
    refute Enum.any?(block_declared, &(&1 in ["signup", "onboarding"]))
  end

  @spec declared_ids(String.t()) :: [String.t()]
  defp declared_ids(key) do
    {:ok, fixture} = Charts.fixture(key)

    Enum.map(fixture.document.datamodel, & &1.id)
  end

  # `card_processing` leaves `myapp.legacy_check` unregistered on purpose,
  # so it needs the suite's stand-in to reach a compiled chart at all;
  # everything else goes through the app's one compile recipe.
  @spec compile!(map()) :: String.t()
  defp compile!(%{key: "card_processing"} = fixture) do
    {:ok, compiled} =
      Compiler.compile(fixture.document, stand_in_palette(),
        known_invoke_types: Charts.invoke_types(),
        declare: fixture.declare,
        terminate: true
      )

    compiled.scxml
  end

  defp compile!(fixture) do
    {:ok, compiled} = Durable.compile(fixture.document, fixture.declare)

    compiled.scxml
  end

  @spec stand_in_palette() :: Palette.t()
  defp stand_in_palette do
    palette = Charts.palette()

    %{palette | types: Map.put(palette.types, "myapp.legacy_check", LegacyCheck)}
  end

  @spec data_ids(String.t()) :: [String.t()]
  defp data_ids(scxml) do
    ~r/<data\b[^>]*\bid="([^"]*)"/
    |> Regex.scan(scxml)
    |> Enum.map(&Enum.at(&1, 1))
  end

  @spec loaded_roots(String.t()) :: [String.t()]
  defp loaded_roots(scxml) do
    ["cond", "expr", "location"]
    |> Enum.flat_map(&attribute_values(scxml, &1))
    |> Enum.flat_map(&roots/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @spec attribute_values(String.t(), String.t()) :: [String.t()]
  defp attribute_values(scxml, attribute) do
    ~r/\b#{attribute}="([^"]*)"/
    |> Regex.scan(scxml)
    |> Enum.map(&(&1 |> Enum.at(1) |> unescape()))
  end

  @spec roots(String.t()) :: [String.t()]
  defp roots(expression) do
    case Predicator.compile(expression) do
      {:ok, instructions} ->
        for ["load", root] <- instructions, do: root

      # An attribute that is not an expression at all - there is none in
      # the shipped fixtures, and a new one would be worth seeing rather
      # than skipping past.
      {:error, error} ->
        flunk("#{inspect(expression)} does not parse: #{inspect(error)}")
    end
  end

  @spec unescape(String.t()) :: String.t()
  defp unescape(value) do
    value
    |> String.replace("&quot;", "\"")
    |> String.replace("&apos;", "'")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&amp;", "&")
  end
end
