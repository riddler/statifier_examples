defmodule StatifierExamples.Signup.Path do
  @moduledoc """
  A **Path**: one block document, plus the element document screens its
  `myapp.screen` blocks name (Riddler R10a).

  The two halves are separate files on purpose
  (`StatifierExamples.Signup.Screens` says why), and separate files can
  disagree. This module is the check that they do not, and it exists
  because one of the disagreements is silent.

  ## Response keys are unique across a Path (R10d)

  A response lands at `responses.<element_key>`. The key is therefore not a
  per-screen identifier but a **Path-wide name**, and two screens on the
  same Path declaring the same key are two questions writing one response:
  the second screen's reader sees the first screen's value already there,
  and whichever is answered last wins. Nothing raises. A compiler cannot
  catch it either - the element document is not a block document and the
  compiler never reads it - so the check has to live here, on the host
  side, which is exactly the class of check `statifier_blocks`' own
  `docs/host-validators.md` is about.

  `validate/1` reports it, with both blocks named.

  **Response keys, not every element key.** The read is
  `StatifierExamples.Signup.Screens.response_keys/1`, which is `text_question`
  nodes and nothing else, so what this holds unique is the keys that carry
  a response - hence `:duplicate_response_key` rather than a tag claiming the
  whole of R10d. Two screens sharing a `heading` or `button` key are not
  reported. That is a gap and not a decision; the spike document records it.

  ## Outcome names are unique across a Path

  The same argument, one step along. `StatifierExamples.Signup.Screen`
  turns a button's declared outcome into the event its press raises, and
  it deliberately does **not** put the screen in that event name - so two
  screens declaring one outcome name compile to two handlers listening for
  one event, and pressing either button interrupts whichever screen the
  execution happens to be sitting in. That one is not silent so much as
  spectacular, and it is the same shape of mistake, so it is the same
  check.

  ## A re-visit through a declared back edge is not a duplicate

  A screen reached twice is not always two questions racing for one
  response key. A Back button is the Path deliberately showing a reader a
  screen they have already seen so they can change what they answered, and
  the overwrite that follows is the point of pressing it rather than the
  hazard this module is about.

  What tells the two apart is **where the second block sits**. A block
  inside a declared `on_<outcome>` slot - the slot a block type opens for
  one of its outcomes, `statifier_blocks`' `on_` naming - is on a branch
  the Path took off its forward line, so a `myapp.screen` block there
  naming a screen key an **earlier** block already named is a *re-visit*,
  and `validate/1` drops it before either uniqueness rule runs. It is the
  screen key that decides, not the block id: the re-visiting block is its
  own block with its own id, and has to be, which is exactly why the flat
  walk `screen_refs/1` answers cannot see the difference on its own.

  Only the repeat is dropped, and only backwards. The first block to name
  a key is never dropped, so two screens racing for one response key or
  one outcome are still reported however they are nested; a screen shown
  twice on the forward line, with no `on_` slot between it and the Path's
  spine, is still reported; and a block in an `on_` slot naming a screen
  that is only shown *later* is kept, because going back to a screen
  nobody has been shown yet is not going back.

  ## What this does not check

  Whether a key is *spelled* the way a datamodel document declares it -
  that is `statifier_datamodel`'s question and not this skeleton's - and
  element keys that carry no response, which the moduledoc's last paragraph
  is about. A screen the block document names but the element document does
  not declare is answered as a separate `:unknown_screen` finding rather
  than folded into either uniqueness rule, and the back-edge drop never
  spends one: a block in an `on_` slot naming an undeclared screen is
  reported however many earlier blocks named the same key.
  """

  alias StatifierBlocks.{Block, Document}
  alias StatifierExamples.Signup.Screens

  @screen_type "myapp.screen"

  # `statifier_blocks` names the slot a block type opens for one of its
  # outcomes `on_<outcome>`. `myapp.screen` is a composite, so its slots
  # are named by `StatifierBlocks.Composite.outcome_slot/1` (0.32.0, the
  # version `mix.lock` resolves), whose prefix is spelled after
  # `StatifierBlocks.Core.Subchart`'s `@slot_prefix`.
  @outcome_slot_prefix "on_"

  @typedoc """
  One thing wrong with a Path.

  `:unknown_screen` names a `myapp.screen` block whose `screen` param is
  not a key in the element document. `:duplicate_response_key` (a
  `text_question` key, not every element key - see the moduledoc) and
  `:duplicate_outcome` each name the repeated name and every **block** that
  reaches it, in the order the Path visits them.

  The blocks are what is named, rather than the screens, because two of
  them may be one screen: a Path that shows a screen twice reaches its keys
  twice, and the second visit overwrites what the first one collected. That
  is the same hazard as two screens sharing a key and it is reported the
  same way - which a finding naming screens could not do, both visits
  having the same screen's name.

  A second visit reached through a declared `on_<outcome>` slot is not one
  of them: it is a re-visit, and no finding names it at all. The
  moduledoc's back-edge section says why.
  """
  @type finding ::
          {:unknown_screen, block_id :: String.t(), screen_key :: String.t()}
          | {:duplicate_response_key, key :: String.t(), block_ids :: [String.t()]}
          | {:duplicate_outcome, outcome :: String.t(), block_ids :: [String.t()]}

  @doc """
  The screen keys `document`'s `myapp.screen` blocks name, in document
  order, with the block id each came from.

  Duplicated keys are kept, and so are the blocks inside `on_<outcome>`
  slots: this walk de-duplicates nothing and knows nothing about back
  edges. Which repeat is a defect and which is a reader going back is
  `validate/1`'s question, and it needs the slot each block sits in, which
  a flat list of pairs has already thrown away.
  """
  @spec screen_refs(Document.t()) :: [{String.t(), String.t()}]
  def screen_refs(%Document{} = document) do
    for %Block{type: @screen_type, id: id, config: config} <- Document.blocks(document),
        do: {id, Map.get(config, "screen", "")}
  end

  @doc """
  Every finding about `document` as a Path, or `[]`.

  Re-visits reached through a declared back edge are dropped before
  either uniqueness rule runs - the moduledoc's back-edge section is the
  rule, and the second example here is it. The drop spends known screens
  only: every block naming a screen the element document does not
  declare is reported as `:unknown_screen`, a back edge included.

  ## Examples

      iex> document = StatifierExamples.Signup.Path.document()
      iex> StatifierExamples.Signup.Path.validate(document)
      []

  A back edge to a screen already shown answers nothing, even though the
  block in the `on_went_back` slot is its own block with its own id:

      iex> alias StatifierBlocks.{Block, Document}
      iex> back = Block.new("myapp.screen", id: "blk_back", config: %{"screen" => "account"})
      iex> plan =
      ...>   Block.new("myapp.screen",
      ...>     id: "blk_plan",
      ...>     config: %{"screen" => "plan"},
      ...>     slots: %{"on_went_back" => [back]}
      ...>   )
      iex> account = Block.new("myapp.screen", id: "blk_account", config: %{"screen" => "account"})
      iex> root = Block.new("core.sequence", id: "blk_root", slots: %{"body" => [account, plan]})
      iex> StatifierExamples.Signup.Path.validate(Document.new(root))
      []
  """
  @spec validate(Document.t()) :: [finding()]
  def validate(%Document{} = document) do
    {known, unknown} =
      document |> screen_refs() |> Enum.split_with(fn {_id, key} -> Screens.screen(key) end)

    known = drop_revisits(known, document)

    Enum.map(unknown, fn {id, key} -> {:unknown_screen, id, key} end) ++
      duplicates(known, :duplicate_response_key, &Screens.response_keys/1) ++
      duplicates(known, :duplicate_outcome, &Screens.outcomes/1)
  end

  @doc """
  The Path document this app ships, decoded.
  """
  @spec document() :: Document.t()
  def document do
    %{document: document} =
      Enum.find(StatifierExamples.Signup.fixtures(), &(&1.key == "signup_path"))

    document
  end

  # The known refs left once the back edges are spent: a screen ref whose
  # screen key an earlier ref already named, and whose block sits inside a
  # declared `on_<outcome>` slot, is a re-visit and takes part in no rule.
  # The first ref naming a key always survives - dropping it too would
  # hide a second, different screen that shares one of its keys, and the
  # walk is pre-order so "first" is the Path's own order.
  @spec drop_revisits([{String.t(), String.t()}], Document.t()) :: [{String.t(), String.t()}]
  defp drop_revisits(refs, document) do
    {kept, _seen} =
      Enum.reduce(refs, {[], MapSet.new()}, fn {id, key} = ref, {kept, seen} ->
        if MapSet.member?(seen, key) and back_edge?(document, id) do
          {kept, seen}
        else
          {[ref | kept], MapSet.put(seen, key)}
        end
      end)

    Enum.reverse(kept)
  end

  # Whether the block carrying `id` sits anywhere inside a slot named for
  # an outcome. `Document.fetch_path/2` answers with every
  # `{parent block id, slot name, index}` step taken to reach the block, so
  # the whole ancestry is in the answer and a screen nested further down
  # inside a back-edge slot counts as one too.
  @spec back_edge?(Document.t(), String.t()) :: boolean()
  defp back_edge?(document, id) do
    case Document.fetch_path(document, id) do
      {:ok, path} ->
        Enum.any?(path, fn {_parent_id, slot, _index} ->
          String.starts_with?(slot, @outcome_slot_prefix)
        end)

      :error ->
        false
    end
  end

  # One pass for both rules: the names `read` pulls off the screen each
  # block refers to, grouped by name, and every group reached by more than
  # one block reported against those blocks. Findings are sorted by the
  # repeated name so the list does not move with the document's block order.
  @spec duplicates([{String.t(), String.t()}], atom(), (Screens.screen() -> [String.t()])) ::
          [finding()]
  defp duplicates(known, tag, read) do
    known
    |> Enum.flat_map(fn {id, screen_key} ->
      screen_key |> Screens.screen() |> read.() |> Enum.map(&{&1, id})
    end)
    |> Enum.group_by(fn {name, _id} -> name end, fn {_name, id} -> id end)
    |> Enum.filter(fn {_name, ids} -> length(ids) > 1 end)
    |> Enum.sort_by(fn {name, _ids} -> name end)
    |> Enum.map(fn {name, ids} -> {tag, name, ids} end)
  end
end
