defmodule StatifierExamples.Charts.StepLabelTest do
  @moduledoc """
  The `label` field every host block type declares, read from the two
  places it has to hold: the schema each type hands the inspector, and the
  shipped fixtures that have carried `config["label"]` since the port.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.Compiler
  alias StatifierBlocks.Palette
  alias StatifierExamples.Charts
  alias StatifierExamples.Test.LegacyCheck

  @label_field %{
    key: "label",
    type: :string,
    label: "Label",
    required?: false,
    default: ""
  }

  # Every type this app registers, both domains, rather than a list spelled
  # out here: a type added later that forgets the field is exactly what this
  # test is for, and a hand-written list would not see it.
  #
  # The `core.*` half of the palette is deliberately not in reach. Whether
  # `core.invoke` declares a label is `statifier_blocks`' decision and its
  # file to change; this app registering a shadow declaration for someone
  # else's type is the local workaround CLAUDE.md forbids.
  @host_types Charts.palette().types
              |> Enum.filter(fn {type, _module} -> String.starts_with?(type, "myapp.") end)
              |> Enum.map(fn {_type, module} -> module end)
              |> Enum.uniq()

  # Sabotage: dropped label_field/0 from the step config_schema/2; this
  # went red, then reverted. One mutation reaches every host type now that
  # both domains route through the one helper; it took two before se-lin.
  test "every host block type declares label, first in the inspector form" do
    for module <- @host_types do
      assert [first | _rest] = module.config_schema(%{}),
             "#{inspect(module)} declares no fields at all"

      assert first == @label_field,
             "#{inspect(module)} does not lead its schema with the label field"
    end
  end

  # The declaration is what `StatifierBlocks.ViewModel.title/1` reads: a
  # `:string` field keyed "label", nothing else. Asserting the two halves the
  # package matches on keeps a well-meaning relabel of the *form* label
  # ("Name", say) from silently un-titling every card.
  #
  # Sabotage: renamed the field's key to "title"; this went red, then
  # reverted.
  test "the declaration is the shape the package titles a card from" do
    for module <- @host_types do
      assert Enum.find(module.config_schema(%{}), &(&1.key == "label" and &1.type == :string))
    end
  end

  # The acceptance criterion's other half: declaring a field a document
  # already carries must not itself become a finding. Every fixture is
  # compiled - card processing through the stand-in palette, because its one
  # deliberate unresolvable type stops the compile before anything downstream
  # is seen - and nothing anywhere may name the key.
  #
  # Sabotage: made Intake.validate_config/1 seed its finding list with
  # {"label", "unknown field label"}; this went red, then reverted.
  test "no fixture reports a finding that names label" do
    for fixture <- Charts.fixtures() do
      for message <- findings(fixture.document) do
        refute message =~ "label",
               "#{fixture.key} reports a finding naming label: #{message}"
      end
    end
  end

  # The labels the declaration reaches, counted per fixture and split at the
  # boundary that decides whether it reaches them: a `myapp.*` block is
  # titled by the field this app declares, and a `core.*` block is not,
  # because no type in that vocabulary declares one (ADR-0002 amendment H5).
  # The `core.*` half is therefore zero everywhere and stays zero - se-62u
  # dropped the thirteen labels that half used to count, since a key nothing
  # reads is not a remainder waiting on an upstream declaration, it is dead
  # data in a shipped example. Counting the half that is empty is the point:
  # it is what fails if one creeps back in through a fixture edit.
  #
  # Sabotage: made Signup.fixtures/0 drop its first document; this went red
  # on the missing key, then reverted.
  test "the fixtures carry the labels the declaration reaches" do
    counts =
      Map.new(Charts.fixtures(), fn fixture ->
        labelled = fixture.document.root |> blocks() |> Enum.filter(&labelled?/1)

        {fixture.key, {Enum.count(labelled, &host?/1), Enum.count(labelled, &(not host?(&1)))}}
      end)

    assert counts == %{
             "card_processing" => {17, 0},
             "signup_invitations" => {1, 0},
             "signup_wizard" => {7, 0}
           }
  end

  @spec findings(StatifierBlocks.Document.t()) :: [String.t()]
  defp findings(document) do
    case Compiler.compile(document, stand_in_palette(), known_invoke_types: Charts.invoke_types()) do
      {:ok, compiled} -> Enum.map(compiled.warnings, & &1.message)
      {:error, findings} -> Enum.map(findings, & &1.message)
    end
  end

  @spec stand_in_palette() :: Palette.t()
  defp stand_in_palette do
    palette = Charts.palette()

    %{palette | types: Map.put(palette.types, "myapp.legacy_check", LegacyCheck)}
  end

  defp labelled?(block), do: is_binary(Map.get(block.config, "label"))

  defp host?(block), do: String.starts_with?(block.type, "myapp.")

  defp blocks(block) do
    [block | block.slots |> Map.values() |> List.flatten() |> Enum.flat_map(&blocks/1)]
  end
end
