defmodule StatifierExamples.Charts.StepTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.{Compiler, Decode}
  alias StatifierExamples.Charts

  # The leaf-step shape both example domains declare themselves on -
  # `StatifierBlocks.InvokeStep`, since se-4dt.1 - asserted end to end through
  # this app's own types rather than against the base directly. The rule
  # easiest to lose is what a step means when its config stores no
  # `invoke_type` at all, so both domains are in the document below:
  # `myapp.receipt` from card processing and `myapp.provision` from the
  # wizard, each with an empty config.
  #
  # The shipped fixtures all author the key, so nothing else in the suite
  # walks this path.
  #
  # The sabotage notes below name functions that were this app's own when the
  # notes were written and are `StatifierBlocks.InvokeStep`'s since se-4dt.1.
  # The mutations were run against the app's copy; the tests are unchanged and
  # still pass against the base.

  # Sabotage: made invoke_type/2 answer "" for an absent key; this went
  # red with an invoke_type finding, then reverted.
  test "a step that stores no invoke type names the one its schema declares" do
    assert {:ok, compiled} = compile(document(%{}, %{}))

    assert compiled.warnings == []
    assert compiled.scxml =~ ~s(type="myapp:receipt")
    assert compiled.scxml =~ ~s(type="myapp:provision")
  end

  # Sabotage: made emit/4 ignore its `default` argument and read only
  # the config; this went red, then reverted.
  test "a stored invoke type is what the call names" do
    config = %{"invoke_type" => "myapp:notify"}

    assert {:ok, compiled} = compile(document(config, config))

    assert compiled.warnings == []
    assert compiled.scxml =~ ~s(type="myapp:notify")
    refute compiled.scxml =~ ~s(type="myapp:receipt")
  end

  # se-dyo. The helper's second job: what the call ANSWERS with. A step
  # naming an `assign_to` writes the handler's result there, on the
  # success transition rather than in a `<finalize>`, which is
  # `StatifierBlocks.Core.Invoke`'s shape for the same key - the answer is
  # only an answer when the call succeeded.
  #
  # The assertion is on the transition rather than on the `<assign>` alone,
  # because an assign anywhere else in the state would be a different
  # promise: an unconditional write of whatever event arrived.
  #
  # Sabotage: moved the `<assign>` from the done transition onto the inner
  # state's `<onexit>`; this went red, then reverted.
  test "a step naming a place for its answer assigns the result on the success transition" do
    config = %{"invoke_type" => "myapp:receipt", "assign_to" => "receipt"}

    assert {:ok, compiled} = compile(document(config, %{}))

    assert compiled.warnings == []

    assert compiled.scxml =~
             ~s(<transition event="done.invoke" target="s_blk_sd_receipt__o_done">) <>
               ~s(<assign expr="_event.data" location="receipt"/></transition>)
  end

  # The other half, and the one that keeps every step in this app that
  # keeps nothing exactly as it was: no key, no `<assign>`.
  #
  # Sabotage: made assign/1 answer the `<assign>` list for a nil
  # location too; this went red, then reverted.
  test "a step that names no place for its answer emits no assign at all" do
    assert {:ok, compiled} = compile(document(%{}, %{}))

    assert compiled.warnings == []
    refute compiled.scxml =~ "<assign"
  end

  # An `assign_to` that is not a bare identifier is a finding on the
  # author's own key, not an attribute the engine cannot read. `myapp.provision`
  # is the block here because it declares no `assign_to` of its own, so the
  # refusal can only be coming from the shared emission path.
  #
  # Sabotage: made assign/1 fall through to the identifier branch for
  # any binary; this went red - the document compiled - then reverted.
  test "an assign_to that is not an identifier is refused at the author's key" do
    assert {:error, findings} =
             compile(document(%{}, %{"assign_to" => "signup.plan"}))

    assert Enum.any?(findings, fn finding ->
             finding.block_id == "blk_sd_provision" and finding.config_key == "assign_to" and
               finding.fault == :author and finding.severity == :error
           end)
  end

  # se-dyo's side effect, pinned because it is a behaviour change rather
  # than a new surface: `StatifierExamples.CardAuth.Authorize` has always
  # DECLARED `assign_to` - required, and a datamodel path - and validated
  # it, but it emits through the shared shape, which until then built two
  # bare transitions. An author's decision key was accepted and then silently
  # dropped. It is live now, and this is what says so.
  #
  # Sabotage: reverted emit/4's `with` clause to ignore
  # `config["assign_to"]`; this went red, then reverted.
  test "myapp.authorize's declared assign_to reaches the chart" do
    assert {:ok, compiled} = compile(authorizing("authorization"))

    assert compiled.warnings == []
    assert compiled.scxml =~ ~s(<assign expr="_event.data" location="authorization"/>)
  end

  @spec compile(StatifierBlocks.Document.t()) :: {:ok, term()} | {:error, term()}
  defp compile(document) do
    Compiler.compile(document, Charts.palette(), known_invoke_types: Charts.invoke_types())
  end

  @spec document(map(), map()) :: StatifierBlocks.Document.t()
  defp document(receipt_config, provision_config) do
    json = """
    {
      "schema_version": 1,
      "id": "bdoc_step_defaults",
      "revision": 1,
      "metadata": {"name": "Step defaults"},
      "root": {
        "type": "core.sequence",
        "id": "blk_sd_root",
        "type_version": 1,
        "slots": {
          "body": [
            {
              "type": "myapp.receipt",
              "id": "blk_sd_receipt",
              "type_version": 1,
              "config": #{Jason.encode!(receipt_config)}
            },
            {
              "type": "myapp.provision",
              "id": "blk_sd_provision",
              "type_version": 1,
              "config": #{Jason.encode!(provision_config)}
            }
          ]
        }
      }
    }
    """

    assert {:ok, document} = Decode.decode(json)

    document
  end

  # A one-block document holding the card-processing step that requires an
  # `assign_to`. It is here rather than in the card-auth tests because the
  # emission it is asserting is the shared base's, reached by both domains.
  @spec authorizing(String.t()) :: StatifierBlocks.Document.t()
  defp authorizing(assign_to) do
    config = %{"invoke_type" => "myapp:authorize", "assign_to" => assign_to}

    json = """
    {
      "schema_version": 1,
      "id": "bdoc_step_assign",
      "revision": 1,
      "metadata": {"name": "Step assign"},
      "root": {
        "type": "myapp.authorize",
        "id": "blk_sa_authorize",
        "type_version": 2,
        "config": #{Jason.encode!(config)}
      }
    }
    """

    assert {:ok, document} = Decode.decode(json)

    document
  end
end
