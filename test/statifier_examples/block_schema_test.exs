defmodule StatifierExamples.BlockSchemaTest do
  @moduledoc """
  Every block document this app ships, checked against the block document's
  JSON Schema that `statifier_blocks` publishes (`StatifierBlocks.Schema`,
  draft-07), with a draft-07 validator of the host's own choosing, the way
  the schema's moduledoc says a host uses it.

  The shipped block documents are found by glob rather than listed, so a
  document added under `priv/fixtures/` or `priv/first_workflow/` is
  checked without anyone remembering to add it here. The two files under
  `priv/fixtures/` that are not block documents are named below, and the
  test proves that each is not one.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.Document
  alias StatifierBlocks.Schema

  @globs ["priv/fixtures/*.json", "priv/first_workflow/*.json"]

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

  # Sabotage: added a required property to the root of the dependency's
  # shipped schema file and recompiled it; the package still accepted every
  # document and this went red on the schema assertion. Restored from a
  # copy.
  test "every shipped block document validates against the published schema" do
    schema = root_schema()
    documents = block_documents()

    assert "priv/first_workflow/hold_pickup.json" in documents
    assert "priv/fixtures/library_loan.json" in documents

    for path <- documents do
      bytes = File.read!(path)

      assert {:ok, %Document{}} = Document.from_json(bytes),
             "#{path} is not a block document the package accepts"

      assert :ok == ExJsonSchema.Validator.validate(schema, Jason.decode!(bytes)),
             "#{path} fails the published block-document schema"
    end
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
