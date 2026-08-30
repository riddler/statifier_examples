defmodule StatifierExamples.Charts.StepTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.{Compiler, Decode}
  alias StatifierExamples.Charts

  # The app's one step helper, asserted on the rule that is easiest to lose
  # when two helpers become one: what a step means when its config stores no
  # `invoke_type` at all. Both domains reach the rule through
  # `StatifierExamples.Charts.Step` now, so both are in the document below -
  # `myapp.receipt` from card processing and `myapp.provision` from the
  # wizard, each with an empty config.
  #
  # The shipped fixtures all author the key, so nothing else in the suite
  # walks this path.

  # Sabotage: made Step.invoke_type/2 answer "" for an absent key; this went
  # red with an invoke_type finding, then reverted.
  test "a step that stores no invoke type names the one its schema declares" do
    assert {:ok, compiled} = compile(document(%{}, %{}))

    assert compiled.warnings == []
    assert compiled.scxml =~ ~s(type="myapp:receipt")
    assert compiled.scxml =~ ~s(type="myapp:provision")
  end

  # Sabotage: made Step.emit/4 ignore its `default` argument and read only
  # the config; this went red, then reverted.
  test "a stored invoke type is what the call names" do
    config = %{"invoke_type" => "myapp:notify"}

    assert {:ok, compiled} = compile(document(config, config))

    assert compiled.warnings == []
    assert compiled.scxml =~ ~s(type="myapp:notify")
    refute compiled.scxml =~ ~s(type="myapp:receipt")
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
end
