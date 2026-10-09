defmodule StatifierExamples.BlockSchemaTest do
  @moduledoc """
  Every block document this app ships, checked against the block document's
  JSON Schema that `statifier_blocks` publishes (`StatifierBlocks.Schema`,
  draft-07), with a draft-07 validator of the host's own choosing, the way
  the schema's moduledoc says a host uses it.

  The shipped block documents are found by glob rather than listed, so a
  document added under `priv/fixtures/`, `priv/first_workflow/` or
  `priv/form_post/` is checked without anyone remembering to add it here.
  The two files under `priv/fixtures/` that are not block documents are
  named below, and the test proves that each is not one.

  From `statifier_blocks` 0.38.0 a block type's declared field types bind,
  so the same documents are also checked against the stricter,
  palette-aware schema `StatifierBlocks.Schema.for_palette/1` answers for
  the palette that authored them, and every palette this app mounts is run
  through the package's pre-flight (`StatifierBlocks.Palette.preflight/1`
  and `preflight/2`), which must answer no finding. The app mounts two:
  `StatifierExamples.Charts.palette/0`, which authored every shipped
  document and which the editor, the Plan view and every compile use, and
  `StatifierBlocks.Palette.core/0`, which the Plan map reads type
  explanations from.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.Document
  alias StatifierBlocks.Palette
  alias StatifierBlocks.Schema
  alias StatifierExamples.Charts

  @globs ["priv/fixtures/*.json", "priv/first_workflow/*.json", "priv/form_post/*.json"]

  # Not block documents, so the block document's schema is not about them:
  # a datamodel document (`statifier_datamodel`'s shape, versioned by
  # `version` and holding `scopes`) and an element document (the signup
  # wizard's screens, holding `screens`). Neither has a `root` block.
  @not_block_documents [
    "priv/fixtures/card-processing.datamodel.json",
    "priv/fixtures/signup_screens.json"
  ]

  defp shipped_json do
    @globs |> Enum.flat_map(&Path.wildcard/1) |> Enum.sort()
  end

  defp block_documents, do: shipped_json() -- @not_block_documents

  defp root_schema, do: Schema.json() |> Jason.decode!() |> ExJsonSchema.Schema.resolve()

  defp palette_schema(palette),
    do: palette |> Schema.for_palette() |> ExJsonSchema.Schema.resolve()

  # Every palette this app mounts, by the name a failure message uses.
  defp mounted_palettes do
    [{"Charts.palette/0", Charts.palette()}, {"Palette.core/0", Palette.core()}]
  end

  # Sabotage: added a required property to the root of the dependency's
  # shipped schema file and recompiled it; the package still accepted every
  # document and this went red on the schema assertion. Restored from a
  # copy.
  test "every shipped block document validates against the published schema" do
    schema = root_schema()
    documents = block_documents()

    assert "priv/first_workflow/hold_pickup.json" in documents
    assert "priv/fixtures/library_loan.json" in documents
    assert "priv/form_post/card_application.json" in documents

    for path <- documents do
      bytes = File.read!(path)

      assert {:ok, %Document{}} = Document.from_json(bytes),
             "#{path} is not a block document the package accepts"

      assert :ok == ExJsonSchema.Validator.validate(schema, Jason.decode!(bytes)),
             "#{path} fails the published block-document schema"
    end
  end

  # Sabotage: set `"assign_to"` of the `core.invoke` block in
  # priv/first_workflow/hold_pickup.json to an integer; this went red on the
  # palette-schema assertion while the published-schema test stayed green.
  # Restored from a copy.
  test "every shipped block document validates against its palette's schema" do
    schema = palette_schema(Charts.palette())
    documents = block_documents()

    assert "priv/first_workflow/hold_pickup.json" in documents
    assert "priv/fixtures/library_loan.json" in documents
    assert "priv/form_post/card_application.json" in documents

    for path <- documents do
      assert :ok ==
               ExJsonSchema.Validator.validate(schema, path |> File.read!() |> Jason.decode!()),
             "#{path} fails the schema for the palette that authored it"
    end
  end

  # Sabotage: set the `retries` default of `myapp.capture` to the string
  # "2" in lib/statifier_examples/card_auth/capture.ex; this went red naming
  # the type. Restored from a copy.
  test "the pre-flight finds nothing in any palette this app mounts" do
    host_types =
      Charts.palette().types |> Map.keys() |> Enum.filter(&String.starts_with?(&1, "myapp."))

    assert host_types != [], "the pre-flight has no host type to judge"

    for {name, palette} <- mounted_palettes() do
      assert {name, []} == {name, Palette.preflight(palette)}
    end
  end

  # Sabotage: the same integer `"assign_to"` in hold_pickup.json as above;
  # this went red with a finding naming the block. Restored from a copy.
  test "the pre-flight finds nothing in any shipped block document" do
    documents =
      for path <- block_documents() do
        {:ok, document} = path |> File.read!() |> Document.from_json()
        document
      end

    assert [] == Palette.preflight(Charts.palette(), documents)
  end

  test "each skipped file is not a block document" do
    for path <- @not_block_documents do
      assert path in shipped_json(), "#{path} is skipped but no longer shipped"

      json = path |> File.read!() |> Jason.decode!()
      refute Map.has_key?(json, "root"), "#{path} carries a root block"
      assert {:error, _reason} = path |> File.read!() |> Document.from_json()
    end
  end

  test "the validator refuses a document the schema does not admit" do
    json = "priv/fixtures/library_loan.json" |> File.read!() |> Jason.decode!()

    assert {:error, [_ | _]} =
             ExJsonSchema.Validator.validate(root_schema(), Map.delete(json, "root"))
  end
end
