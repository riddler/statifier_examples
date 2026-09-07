defmodule StatifierExamples.Charts.TypedEnvironmentTest do
  @moduledoc """
  The card-processing domain declares its own types, and the read check
  answers both ways over the document this app ships.

  `statifier_blocks` ADR-0011 defines the environment: a map from datamodel
  path to type, carried through a document in pre-order, against which a
  block's read signature is checked. `statifier_datamodel`'s `sd-ADR-0001`
  owns the document those types are declared in and the check itself. This
  app is the reference embedder for both, so what is asserted here is the
  host's half - that the declarations are reachable, that the shipped
  document is clean under them, and that the one refusal the domain is
  authored to demonstrate is a single field value away.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Assignability, Compiler, Document, Edit, Environment}
  alias StatifierDatamodel.Declarations
  alias StatifierExamples.Charts

  @subject "cards.current_txn"

  setup do
    {:ok, fixture} = Charts.fixture("card_processing")

    %{fixture: fixture, document: fixture.document, datamodel: fixture.datamodel}
  end

  describe "the datamodel document" do
    # Sabotage: renamed `priv/fixtures/card-processing.datamodel.json` to
    # `card_processing.datamodel.json`, so the domain key missed; both card
    # fixtures came back `nil` and this went red. Reverted from a backup
    # copy.
    test "is keyed on the domain, so both card-processing charts share one", %{
      datamodel: datamodel
    } do
      {:ok, sketch} = Charts.fixture("card_processing_sketch")

      assert is_map(datamodel)
      assert sketch.datamodel == datamodel
    end

    # Sabotage: gave `signup_wizard.json` the domain `card-processing`; the
    # wizard picked the card vocabulary up and this went red. Reverted from
    # a backup copy.
    test "is absent for a domain that declares none" do
      {:ok, wizard} = Charts.fixture("signup_wizard")

      assert wizard.datamodel == nil
    end

    # The three declarations the flow is written against. `types` is the
    # datamodel document's fourth key and contributes no paths: it says what
    # a path may hold, never that one exists.
    #
    # Sabotage: dropped the `label` from the `cards.settlement`
    # declaration; the label read back as the nominal name and this went
    # red. Reverted from a backup copy.
    test "declares the two records and the shape the flow reads", %{datamodel: datamodel} do
      declarations = Declarations.from_document(datamodel)

      assert Environment.type_label(declarations, "cards.credit_txn") ==
               "Credit card transaction"

      assert Environment.type_label(declarations, "cards.settlement") == "Settlement"
      assert Environment.type_label(declarations, "Settleable") == "Settleable"

      declared = StatifierDatamodel.Document.declared_paths(datamodel)

      refute MapSet.member?(declared, "cards.credit_txn")
      assert MapSet.member?(declared, @subject)
    end
  end

  describe "the satisfied read" do
    # The subject path is seeded by the entry block, which is the first
    # block of the root's body slot - `myapp.intake`, whose palette entry
    # names `cards.current_txn` and whose `produces` writes a
    # `cards.credit_txn` there.
    #
    # Sabotage: removed `subject:` from `CardAuth.Intake`'s palette entry;
    # the subject path was absent from the environment and this went red.
    # Reverted from a backup copy.
    test "the entry block seeds the subject with the transaction record", %{
      document: document,
      datamodel: datamodel
    } do
      env =
        Environment.at(Charts.palette(), document, {"blk_cp_root", "body", 1}, %{
          datamodel: datamodel
        })

      assert Map.fetch!(env, @subject) == "cards.credit_txn"
    end

    # `myapp.capture`'s `consumes: "Settleable"` is a read at that same
    # subject path. A credit card transaction is not a Settleable by
    # identity - nothing declares the two related - and the read passes on
    # COVERAGE: the record carries every field the shape requires.
    #
    # Sabotage: dropped the whole `Settleable` declaration from the
    # document's `types` list; the read stopped being a coverage question
    # at all and this went red. Reverted from a backup copy.
    test "a transaction covers the shape a capture asks for", %{datamodel: datamodel} do
      declarations = Declarations.from_document(datamodel)

      assert Environment.satisfies(declarations, "cards.credit_txn", "Settleable") == :covers
    end

    # The whole document, checked at once: the shipped bytes carry no
    # data-flow finding at all, which is what makes the refusal below a
    # thing an author produced rather than a thing that was already there.
    #
    # Sabotage: pointed `CardAuth.Capture`'s `consumes` at
    # `cards.settlement`; the capture step's read stopped being satisfied
    # and this went red. Reverted from a backup copy.
    test "the shipped document is clean under its own declarations", %{
      document: document,
      datamodel: datamodel
    } do
      assert Assignability.validate(Charts.palette(), document, %{datamodel: datamodel}) == :ok
    end
  end

  describe "the refused read" do
    # `myapp.receipt` reads a `cards.settlement` at the path its
    # `settlement` field names. Pointed where the document points it, the
    # document declares that path AS the `cards.settlement` record, so the
    # read meets exactly what it expects and is satisfied. Pointed at the
    # subject, the environment holds a transaction, and two declared
    # records that are not the same record do not widen into one another.
    #
    # Sabotage: renamed the datamodel file off the domain key, so no
    # declarations were in hand; with nothing declared the refusal did not
    # fire and this went red. Reverted from a backup copy.
    test "reading a settlement where the transaction sits is refused, naming the path", %{
      document: document,
      datamodel: datamodel
    } do
      refused = point_receipt_at(document, @subject)

      assert {:error, findings} =
               Assignability.validate(Charts.palette(), refused, %{datamodel: datamodel})

      assert [{:type_mismatch, "blk_cp_receipt", _source, held, expected, path}] = findings
      assert held == "cards.credit_txn"
      assert expected == "cards.settlement"
      assert path == @subject
    end

    # The same refusal as the editor and the compiler report it: a
    # structural finding anchored on the block, whose message renders both
    # types by the LABEL the datamodel document declares rather than by
    # their nominal names.
    #
    # Sabotage: dropped the `label` key from the `cards.settlement`
    # declaration; the message rendered the nominal name and this went red.
    # Reverted from a backup copy.
    test "the compiler reports it against the block, by declared label", %{
      document: document,
      datamodel: datamodel
    } do
      refused = point_receipt_at(document, @subject)

      assert {:error, findings} =
               Compiler.compile(refused, Charts.palette(),
                 known_invoke_types: Charts.invoke_types(),
                 declare: [],
                 datamodel: datamodel,
                 terminate: true
               )

      assert [finding] = findings
      assert finding.block_id == "blk_cp_receipt"
      assert finding.severity == :error
      assert finding.message =~ "Settlement"
      assert finding.message =~ "Credit card transaction"
      assert finding.message =~ @subject
    end

    # And the reason, which is what an author's message is built out of:
    # not a missing field, but two records with no relation at all.
    #
    # Sabotage: redeclared `cards.settlement` as a shape rather than a
    # record; the reason became a coverage answer and this went red.
    # Reverted from a backup copy.
    test "the reason is a plain refusal rather than a shape it nearly covers", %{
      datamodel: datamodel
    } do
      declarations = Declarations.from_document(datamodel)

      assert Environment.satisfies(declarations, "cards.credit_txn", "cards.settlement") ==
               :not_assignable
    end
  end

  describe "the declared kinds the condition editor reads" do
    # `StatifierDatamodel.Index.path_types/1` is what statifier-ui 0.8's
    # clause builder is handed: a path declared `integer` projects to the
    # expression language's `:number`, which is what decides the operator
    # list a clause offers.
    #
    # Sabotage: redeclared `risk_rating` as a string; the projection came
    # back `:string` and this went red. Reverted from a backup copy.
    test "risk_rating is a number, and the enums carry their values", %{datamodel: datamodel} do
      types = StatifierDatamodel.Index.path_types(StatifierDatamodel.Index.index(datamodel))

      assert types["risk_rating"] == :number
      assert types["amount_cents"] == :number
      assert types["card.active"] == :boolean
      assert types["fraud.verdict"] == {:one_of, ["clear", "review", "decline"]}
    end

    # The picklist opens on a clause it can round-trip, and a compound one
    # is not that. The risk branch's high-risk arm is a lone comparison on
    # purpose, so the structured editor is reachable without typing first.
    #
    # Sabotage: put the retired `OR fraud.verdict == ...` half back on the
    # cond; this went red. Reverted from a backup copy.
    test "the risk branch's arm is a lone simple comparison", %{document: document} do
      config = config(document, "blk_cp_risk_branch")

      assert [%{"slot" => "arm_high_risk", "cond" => cond} | _rest] = config["arms"]
      assert cond == "risk_rating >= 70"
      refute cond =~ " OR "
      refute cond =~ " AND "
    end
  end

  @spec point_receipt_at(Document.t(), String.t()) :: Document.t()
  defp point_receipt_at(document, path) do
    config = config(document, "blk_cp_receipt")

    {:ok, refused, _inverse} =
      Edit.apply(
        document,
        {:update_config, "blk_cp_receipt", Map.put(config, "settlement", path)}
      )

    refused
  end

  @spec config(Document.t(), String.t()) :: map()
  defp config(document, id) do
    document
    |> Document.blocks()
    |> Enum.find(&(&1.id == id))
    |> Map.fetch!(:config)
  end
end
