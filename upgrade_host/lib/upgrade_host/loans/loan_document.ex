defmodule UpgradeHost.Loans.LoanDocument do
  @moduledoc """
  The library loan as a `StatifierBlocks.Document`, authored the way an
  author builds it in an editor, and compiled to the chart every loan runs.

  `document/0` starts from the root block and applies one
  `StatifierBlocks.Edit` command per gesture: the datamodel the document
  reads, the events it accepts, then each step inserted and configured.
  Every command passes `StatifierBlocks.Edit.check_config/3` against the
  host's palette before `StatifierBlocks.Edit.apply/2` takes it, which is
  the gate an editor puts in front of a commit.

  The document reads:

      Until loan.returned
        Resume group (shallow)
          Wait 14d
          On loan.renew, resume
        Assess fine (myapp:assess_fine)
        Notify patron (myapp:notify_patron)

  A copy goes out for fourteen days; a renewal re-enters the wait, which
  cancels the timer it had and arms a fresh one; when the wait runs out the
  fine is assessed and the patron told; and the copy coming back finishes
  the loan wherever it is. A fine that cannot be assessed is a failure the
  document does not handle, so the compile sends it to the chart's failed
  final and the loan ends failed.

  The block ids and the document id were minted once, with
  `StatifierBlocks.Id.block/0` and `StatifierBlocks.Id.document/0`, when
  the document was first written, and are fixed since: a block id is
  stable and never reused, and the chart's state ids derive from them, so
  a stored loan and a fresh node agree on every state.

  `compile/0` is the runtime compile through
  `StatifierBlocks.Compiler.compile/3`, with `terminate: true` so a loan
  that ends reaches a top-level final and its execution completes.
  """

  alias StatifierBlocks.{Block, Compiled, Compiler, Document, Edit}
  alias StatifierBlocks.Document.DatamodelEntry
  alias UpgradeHost.Loans.Blocks

  @document_id "bdoc_06ghkym9n1cg7yq95eypz41cp8"

  @ids %{
    loan: "blk_06ghkym9rtacmasp2ej58f9q6r",
    period: "blk_06ghkym9rr3c7vtmqwkx3e9kyc",
    due: "blk_06ghkym9rr1c5qchxjke4x7xkw",
    renew: "blk_06ghkym9rvbkbhj7k2xmfavg10",
    fine: "blk_06ghkym9rvmy97dxwpqkfv529r",
    notice: "blk_06ghkym9rv5qq0xn88m7fa4yq0"
  }

  # The loan period: fourteen days, in the duration grammar `core.wait`
  # reads.
  @loan_period "14d"

  @typedoc "The name each block of the loan document goes by here."
  @type block_name :: :loan | :period | :due | :renew | :fine | :notice

  @doc "The document's id."
  @spec id() :: Document.id()
  def id, do: @document_id

  @doc "The id of the block `name` names."
  @spec block_id(block_name()) :: Block.id()
  def block_id(name), do: Map.fetch!(@ids, name)

  @doc "Every block's name, by its id: the inverse of `block_id/1`."
  @spec names() :: %{Block.id() => block_name()}
  def names, do: Map.new(@ids, fn {name, id} -> {id, name} end)

  @doc """
  The edits that author the document from its root, in the order an
  author makes them.
  """
  @spec edits() :: [Edit.t()]
  def edits do
    [
      {:set_datamodel,
       [
         %DatamodelEntry{id: "copy", description: "The copy on loan."},
         %DatamodelEntry{id: "patron", description: "The patron who has it."},
         %DatamodelEntry{id: "fine", description: "The fine, once one is assessed."}
       ]},
      {:set_accepts, ["loan.renew", "loan.returned"]},
      {:insert, {@ids.loan, "body", 0},
       Block.new("core.resumable_group", id: @ids.period, config: %{"history" => "shallow"})},
      {:insert, {@ids.period, "body", 0},
       Block.new("core.wait", id: @ids.due, config: %{"duration" => @loan_period})},
      {:insert, {@ids.period, "interrupts", 0},
       Block.new("core.on_event",
         id: @ids.renew,
         config: %{"event" => "loan.renew", "outcome" => "resume"}
       )},
      {:insert, {@ids.loan, "body", 1}, Block.new("myapp.assess_fine", id: @ids.fine)},
      {:update_config, @ids.fine, %{"copy" => "copy", "assign_to" => "fine"}},
      {:insert, {@ids.loan, "body", 2}, Block.new("myapp.notify_patron", id: @ids.notice)},
      {:update_config, @ids.notice, %{"patron" => "patron", "fine" => "fine"}}
    ]
  end

  @doc """
  Authors the document: the root, then every edit in `edits/0`, each
  checked by `StatifierBlocks.Edit.check_config/3` and applied by
  `StatifierBlocks.Edit.apply/2`. Answers the first refusal instead when
  one refuses.
  """
  @spec author() :: {:ok, Document.t()} | {:error, term()}
  def author do
    palette = Blocks.palette()

    root =
      Block.new("myapp.until_returned", id: @ids.loan, config: %{"event" => "loan.returned"})

    start =
      Document.new(root,
        id: @document_id,
        revision: 1,
        metadata: %{"name" => "Library loan", "domain" => "library_loan"}
      )

    Enum.reduce_while(edits(), {:ok, start}, fn edit, {:ok, document} ->
      with :ok <- Edit.check_config(palette, document, edit),
           {:ok, edited, _inverse} <- Edit.apply(document, edit) do
        {:cont, {:ok, edited}}
      else
        {:error, reason} -> {:halt, {:error, {edit, reason}}}
      end
    end)
  end

  @doc "The authored document. Raises if the authoring refuses."
  @spec document() :: Document.t()
  def document do
    {:ok, document} = author()
    document
  end

  @doc """
  Compiles `document` against the host's palette, as a root document that
  finishes, with the two invoke types the host registers handlers for.
  """
  @spec compile(Document.t()) :: {:ok, Compiled.t()} | {:error, [Compiler.Finding.t()]}
  def compile(document \\ document()) do
    Compiler.compile(document, Blocks.palette(),
      terminate: true,
      known_invoke_types: ["myapp:assess_fine", "myapp:notify_patron"]
    )
  end
end
