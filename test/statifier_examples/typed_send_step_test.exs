defmodule StatifierExamples.TypedSendStepTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.{BlockType, Compiled, Compiler, Decode, Palette}
  alias StatifierExamples.{Charts, TypedSendStep}

  @config %{"type" => "myapp:sink", "target" => "overdue_notices", "event" => "loan.overdue"}

  # Sabotage: dropped the typed send entry from Charts.registrations/0; this
  # went red on the missing key, then reverted.
  test "the app's palette carries the step beside the core vocabulary" do
    assert %Palette{types: %{"myapp.typed_send" => TypedSendStep, "core.send" => _core}} =
             Charts.palette()
  end

  # Sabotage: made explain/0 answer a string with a newline in it; the
  # resolver dropped it to the palette description and this went red.
  test "the step explains itself through its own explain/0" do
    assert BlockType.explain(TypedSendStep) == TypedSendStep.explain()
  end

  # Sabotage: swapped the target and type values in emit/2; this went red on
  # the send element, then reverted.
  test "with no payload the compiled send carries the literal type, target and event only" do
    for config <- [@config, Map.put(@config, "payload", []), Map.put(@config, "payload", nil)] do
      assert send_element(config) ==
               ~s(<send event="loan.overdue" target="overdue_notices" type="myapp:sink"/>)
    end
  end

  # Sabotage: emitted the payload's params in reverse; this went red on the
  # param order, then reverted.
  test "with a payload the compiled send carries one param per declared path, in order" do
    config = Map.put(@config, "payload", ["loan.id", "loan.copy_id"])

    assert send_element(config) ==
             ~s(<send event="loan.overdue" target="overdue_notices" type="myapp:sink">) <>
               ~s(<param expr="loan.id" name="loan.id"/>) <>
               ~s(<param expr="loan.copy_id" name="loan.copy_id"/>) <>
               "</send>"
  end

  # Sabotage: made payload_findings/1 answer [] for every list; this went red
  # on the first refused payload, then reverted.
  test "a payload that is not a list of distinct datamodel paths is refused" do
    for payload <- [["loan id"], [""], ["loan..id"], [7], ["loan.id", "loan.id"], "loan.id"] do
      answer = TypedSendStep.validate_config(Map.put(@config, "payload", payload))

      assert match?({:error, [{"payload", _message}]}, answer),
             "#{inspect(payload)} was not refused: #{inspect(answer)}"
    end

    assert :ok = TypedSendStep.validate_config(Map.put(@config, "payload", ["loan.id", "_x"]))
  end

  # Sabotage: dropped "event" from @keys; this went red on the missing
  # finding, then reverted.
  test "type, target and event are each the author's to set" do
    for key <- ["type", "target", "event"] do
      assert {:error, [{^key, "must not be empty"}]} =
               TypedSendStep.validate_config(Map.put(@config, key, ""))
    end
  end

  defp send_element(config) do
    document = %{
      "schema_version" => 1,
      "id" => "bdoc_loan_overdue_notice",
      "revision" => 1,
      "metadata" => %{"name" => "Loan overdue notice", "domain" => "library_loan"},
      "root" => %{
        "type" => "core.sequence",
        "id" => "blk_lon_root",
        "type_version" => 1,
        "slots" => %{
          "body" => [
            %{
              "type" => "myapp.typed_send",
              "id" => "blk_lon_tell_desk",
              "type_version" => 1,
              "config" => config
            }
          ]
        }
      }
    }

    {:ok, decoded} = document |> Jason.encode!() |> Decode.decode()

    {:ok, %Compiled{scxml: scxml}} =
      Compiler.compile(decoded, Charts.palette(), datamodel: nil, declare: [])

    assert {:ok, _machine} = Statifier.compile(scxml)

    [element] = Regex.run(~r{<send [^>]*?(?:/>|>.*?</send>)}s, scxml, capture: :first)
    String.replace(element, ~r/>\s+</, "><")
  end
end
