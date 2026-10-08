defmodule UpgradeHost.LoanDocumentTest do
  @moduledoc """
  The loan as a block document, through every `statifier_blocks` call the
  host makes without an editor: its palette and its three block types, the
  authoring edits and their gate, the document's canonical bytes and
  identity, the compile and its record, the publish-time checks, and the
  view model read as an outline.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{
    Assignability,
    Block,
    CompilationRecord,
    Compiled,
    Compiler,
    Document,
    Edit,
    Graph,
    Id,
    Palette,
    Plan,
    Publish,
    ViewModel
  }

  alias StatifierBlocks.Compiler.StateId
  alias StatifierBlocks.Core.{OnEvent, ResumableGroup, Wait}
  alias StatifierBlocks.Document.DatamodelEntry
  alias UpgradeHost.Loans.{Blocks, LoanDocument}
  alias UpgradeHost.Loans.Blocks.{AssessFine, NotifyPatron, UntilReturned}

  # The document's identity and its chart's, at the pinned statifier_blocks.
  # A step that moves either is a finding to record with the step: a moved
  # document hash means the canonical bytes changed, and a moved chart hash
  # means an execution stored on the old chart needs that chart registered
  # to be read back.
  @document_hash "sha256:164ca1c04c5e9597cf535835dc42ac3163e19ff71e6a8b2162c4b7f2d763db49"
  @chart_hash "sha256:7bdd4f497b31dafbb0579abee1b0ac23100e32ac3e187809b1769bf5b91d7866"

  describe "the palette" do
    # sabotage: built the palette from the host's types alone, without
    # Palette.core/0's -> red, the core types were not all in it.
    test "is the core vocabulary with the host's three types on top" do
      palette = Blocks.palette()

      assert Palette.core_types() |> Map.keys() |> Enum.all?(&Map.has_key?(palette.types, &1))
      assert palette.recipes == Palette.core().recipes

      assert {:ok, UntilReturned} = Palette.fetch(palette, "myapp.until_returned")
      assert {:ok, AssessFine} = Palette.fetch(palette, "myapp.assess_fine")
      assert {:ok, NotifyPatron} = Palette.fetch(palette, "myapp.notify_patron")
      assert {:ok, Wait} = Palette.fetch(palette, "core.wait")
    end

    test "carries the two invoke steps, each naming its handler's invoke type" do
      assert AssessFine.invoke_type() == "myapp:assess_fine"
      assert NotifyPatron.invoke_type() == "myapp:notify_patron"

      assert keys(AssessFine) == ["label", "invoke_type", "copy", "assign_to"]
      assert keys(NotifyPatron) == ["label", "invoke_type", "patron", "fine"]

      for step <- [AssessFine, NotifyPatron] do
        assert step.outcomes(%{}) == [{"done", "Done"}, {"error", "Error"}]
        assert step.failure_outcomes(%{}) == ["error"]
        assert Assignability.io(step, %{}) == %{kinds: [:step]}
      end
    end

    # sabotage: UntilReturned.validate_config/1 answered :ok for any event
    # -> red, the blank-separated event was admitted.
    test "carries a block type written against the behaviour, with a body and a sentence" do
      assert UntilReturned.slots(%{}) == [{"body", :any, "Steps"}]
      assert UntilReturned.sentence(%{"event" => "loan.returned"}) == "Until loan.returned"
      assert UntilReturned.validate_config(%{"event" => "loan.returned"}) == :ok

      assert {:error, [{"event", _message}]} =
               UntilReturned.validate_config(%{"event" => "loan returned"})

      assert Assignability.io(UntilReturned, %{}) == %{
               kinds: [:step],
               slot_accepts: %{"body" => [:step]}
             }
    end
  end

  describe "the document" do
    test "is authored edit by edit, and holds the loan's steps in order" do
      assert {:ok, document} = LoanDocument.author()
      assert document == LoanDocument.document()
      assert document.id == LoanDocument.id()

      assert Enum.map(Document.blocks(document), &{&1.id, &1.type}) == [
               {LoanDocument.block_id(:loan), "myapp.until_returned"},
               {LoanDocument.block_id(:period), "core.resumable_group"},
               {LoanDocument.block_id(:due), "core.wait"},
               {LoanDocument.block_id(:renew), "core.on_event"},
               {LoanDocument.block_id(:fine), "myapp.assess_fine"},
               {LoanDocument.block_id(:notice), "myapp.notify_patron"}
             ]

      assert [
               %DatamodelEntry{id: "copy"},
               %DatamodelEntry{id: "patron"},
               %DatamodelEntry{id: "fine"}
             ] =
               document.datamodel

      palette = Blocks.palette()

      for {name, module} <- [due: Wait, renew: OnEvent, period: ResumableGroup] do
        block = find(document, name)
        assert {:ok, ^module} = Palette.fetch(palette, block.type)
      end
    end

    # sabotage: AssessFine.validate_config/1 dropped its copy check -> red,
    # the gate admitted "the copy".
    test "gates every edit through the palette before it applies" do
      document = LoanDocument.document()
      palette = Blocks.palette()
      fine = LoanDocument.block_id(:fine)
      loan = LoanDocument.block_id(:loan)

      assert {:error, {:invalid_config, ^fine, [{"copy", _}]}} =
               Edit.check_config(
                 palette,
                 document,
                 {:update_config, fine, %{"copy" => "the copy"}}
               )

      assert {:error, {:invalid_config, ^loan, [{"event", _}]}} =
               Edit.check_config(palette, document, {:update_config, loan, %{"event" => "x y"}})

      edit = {:update_config, fine, %{"copy" => "copy", "assign_to" => "loan_fine"}}
      assert :ok = Edit.check_config(palette, document, edit)
      assert {:ok, edited, _inverse} = Edit.apply(document, edit)
      assert find(edited, :fine).config["assign_to"] == "loan_fine"
    end

    test "encodes to canonical bytes that decode back to it, under a stable hash" do
      document = LoanDocument.document()
      json = Document.to_json(document)

      assert {:ok, ^document} = Document.from_json(json)
      assert Document.content_hash(document) == @document_hash
    end

    test "takes a block minted with a fresh id, and keeps every other block's states" do
      document = LoanDocument.document()
      palette = Blocks.palette()
      grace = Block.new("core.wait", id: Id.block(), config: %{"duration" => "2d"})
      edit = {:insert, {LoanDocument.block_id(:loan), "body", 3}, grace}

      assert "blk_" <> _ = grace.id
      assert :ok = Edit.check_config(palette, document, edit)
      assert {:ok, edited, _inverse} = Edit.apply(document, edit)
      assert :ok = Plan.expressible(edited, palette, %{})
      assert Document.content_hash(edited) != @document_hash

      assert {:ok, %Compiled{scxml: scxml}} = LoanDocument.compile(edited)
      assert scxml =~ ~s(id="#{StateId.state_id(grace.id)}")

      for name <- [:loan, :period, :due, :renew, :fine, :notice] do
        assert scxml =~ ~s(id="#{StateId.state_id(LoanDocument.block_id(name))}")
      end
    end
  end

  describe "the compile" do
    test "records the join between the document and the chart" do
      assert {:ok, %Compiled{record: record, warnings: []}} = LoanDocument.compile()

      # The compiler version is the statifier_blocks version, so it moves
      # with every release the host takes, a patch included.
      assert %CompilationRecord{
               document_id: document_id,
               revision: 1,
               document_hash: @document_hash,
               compiler_version: "0.37.0",
               accepts: ["loan.renew", "loan.returned"]
             } = record

      assert document_id == LoanDocument.id()
      assert record.chart_identity.content_hash == @chart_hash
      assert record.chart_identity.name == LoanDocument.id()
    end

    # sabotage: LoanDocument.compile/1 compiled the authored document
    # whatever it was handed -> red, the compile answered :ok.
    test "refuses a document whose step config does not check, naming the step and key" do
      fine = LoanDocument.block_id(:fine)

      {:ok, bad, _inverse} =
        Edit.apply(LoanDocument.document(), {:update_config, fine, %{"copy" => "the copy"}})

      assert {:error, [%Compiler.Finding{} = finding]} = LoanDocument.compile(bad)
      assert %{stage: :config, block_id: ^fine, config_key: "copy", severity: :error} = finding
    end
  end

  describe "the publish checks" do
    test "find the document expressible through the host's palette, and only through it" do
      document = LoanDocument.document()
      assert :ok = Plan.expressible(document, Blocks.palette(), %{})

      assert {:no, reasons} = Plan.expressible(document, Palette.core(), %{})

      assert for({:unresolved, id, {:unknown_block_type, type}} <- reasons, do: {id, type}) == [
               {LoanDocument.block_id(:loan), "myapp.until_returned"},
               {LoanDocument.block_id(:fine), "myapp.assess_fine"},
               {LoanDocument.block_id(:notice), "myapp.notify_patron"}
             ]
    end

    test "find nothing to refuse, and no child document to resolve" do
      assert Publish.findings(LoanDocument.document(), Blocks.palette(), %{}) == []

      resolver = fn document_id -> flunk("resolved a child: #{document_id}") end
      assert Graph.check(UpgradeHost.Loans.compiled(), resolver) == []
    end
  end

  describe "the view model" do
    test "reads as an outline of sentences, without an editor" do
      outline =
        LoanDocument.document()
        |> ViewModel.build(Blocks.palette(), [])
        |> ViewModel.outline()
        |> Enum.map(fn {node, depth, kind} -> {node.block_id, depth, kind, node.sentence} end)

      assert outline == [
               {LoanDocument.block_id(:loan), 0, :step, "Until loan.returned"},
               {LoanDocument.block_id(:period), 1, :step, "Resumable group"},
               {LoanDocument.block_id(:due), 2, :step, "Wait 14d"},
               {LoanDocument.block_id(:renew), 2, :rail, "When loan.renew, resume"},
               {LoanDocument.block_id(:fine), 1, :step, "Assess fine"},
               {LoanDocument.block_id(:notice), 1, :step, "Notify patron"}
             ]
    end
  end

  defp keys(module), do: Enum.map(module.config_schema(%{}), & &1.key)

  defp find(document, name) do
    id = LoanDocument.block_id(name)
    Enum.find(Document.blocks(document), &(&1.id == id))
  end
end
