defmodule UpgradeHost.LoanWithNotice do
  @moduledoc """
  A loan whose overdue notice runs as a child execution: two block
  documents and the host callbacks a durable `core.subchart` resolves
  through, for the cascade test in `UpgradeHost.LoanTest`.

  The loan document the host runs opens no subchart, so a loan of its own
  has no child for `StatifierPersistence.Executions.cascade_cancel/3` to
  reach. This document does: the loan holds a `core.subchart` naming the
  notice document, which waits for the notice to be sent.

      Until loan.returned
        Run the overdue notice (statifier_blocks:subchart)

      Overdue notice
        Wait for notice.sent

  `driver/0` is `StatifierPersistence.Driver` over the host's own store,
  with `StatifierBlocks.Runtime.DurableSubchart` answering the subchart,
  so the notice starts as its own execution, linked to the loan under the
  package's reserved metadata key.
  """

  use StatifierBlocks.Runtime.DurableSubchart

  alias StatifierBlocks.{Block, Compiler, Document, Palette}
  alias StatifierBlocks.Runtime.DurableSubchart
  alias StatifierPersistence.Driver
  alias UpgradeHost.Loans
  alias UpgradeHost.Loans.Blocks

  @loan_id "bdoc_06gjps6yjp3yq15x1jx8swjznr"
  @notice_id "bdoc_06gjps6yk4cajvcjt7kf0tb7zc"

  @ids %{
    loan: "blk_06gjps6ykbph59xy1d5vk26dcr",
    run_notice: "blk_06gjps6yk8qat680spghgdkkqm",
    notice: "blk_06gjps6yk9skxaqwn40sf467ym",
    sent: "blk_06gjps6yk9qgt77cqaade98z7c"
  }

  @doc "The id of the loan document's `core.subchart` block, which is the notice's invoke id."
  @spec subchart_block_id() :: Block.id()
  def subchart_block_id, do: @ids.run_notice

  @doc "The loan document: the copy is out until it comes back, and the notice runs as a child."
  @spec loan() :: Document.t()
  def loan do
    root =
      Block.new("myapp.until_returned", id: @ids.loan, config: %{"event" => "loan.returned"})

    subchart =
      Block.new("core.subchart", id: @ids.run_notice, config: %{"chart" => @notice_id})

    root
    |> Document.new(id: @loan_id, revision: 1, metadata: %{"domain" => "library_loan"})
    |> edit({:insert, {@ids.loan, "body", 0}, subchart})
  end

  @doc "The notice document: it waits for the notice to be sent."
  @spec notice() :: Document.t()
  def notice do
    sent = Block.new("core.await", id: @ids.sent, config: %{"event" => "notice.sent"})

    "core.sequence"
    |> Block.new(id: @ids.notice)
    |> Document.new(id: @notice_id, revision: 1, metadata: %{"domain" => "library_loan"})
    |> edit({:insert, {@ids.notice, "body", 0}, sent})
  end

  @doc "The loan document's runtime chart."
  @spec machine() :: Statifier.Machine.t()
  def machine do
    {:ok, compiled} =
      Compiler.compile(loan(), palette(),
        terminate: true,
        known_invoke_types: [DurableSubchart.invoke_type()]
      )

    {:ok, machine} = Statifier.compile(compiled.scxml, chart_name: @loan_id)
    machine
  end

  @doc "A driver over the host's store, the subchart answered durably."
  @spec driver() :: Driver.t()
  def driver, do: Driver.new(Loans.store(), machine(), dispatch: &dispatch/3)

  @impl StatifierBlocks.Runtime.Subchart
  def resolve_chart(@notice_id, _ctx), do: {:ok, notice()}
  def resolve_chart(_document_id, _ctx), do: :error

  @impl StatifierBlocks.Runtime.Subchart
  @spec palette() :: Palette.t()
  def palette, do: Blocks.palette()

  defp edit(document, edit) do
    :ok = StatifierBlocks.Edit.check_config(palette(), document, edit)
    {:ok, edited, _inverse} = StatifierBlocks.Edit.apply(document, edit)
    edited
  end
end
