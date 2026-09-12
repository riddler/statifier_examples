defmodule StatifierExamples.Signup.Path do
  @moduledoc """
  A **Path**: one block document, plus the element document screens its
  `myapp.screen` blocks name (Riddler R10a).

  The two halves are separate files on purpose
  (`StatifierExamples.Signup.Screens` says why), and separate files can
  disagree. This module is the check that they do not, and it exists
  because one of the disagreements is silent.

  ## Element keys are unique across a Path (R10d)

  An answer lands at `answers.<element_key>`. The key is therefore not a
  per-screen identifier but a **Path-wide name**, and two screens on the
  same Path declaring the same key are two questions writing one answer:
  the second screen's reader sees the first screen's value already there,
  and whichever is answered last wins. Nothing raises. A compiler cannot
  catch it either - the element document is not a block document and the
  compiler never reads it - so the check has to live here, on the host
  side, which is exactly the class of check `statifier_blocks`' own
  `docs/host-validators.md` is about.

  `validate/1` reports it, with both screens named.

  ## Outcome names are unique across a Path

  The same argument, one step along. `StatifierExamples.Signup.Screen`
  turns a button's declared outcome into the event its press raises, and
  it deliberately does **not** put the screen in that event name - so two
  screens declaring one outcome name compile to two handlers listening for
  one event, and pressing either button interrupts whichever screen the
  run happens to be sitting in. That one is not silent so much as
  spectacular, and it is the same shape of mistake, so it is the same
  check.

  ## What this does not check

  Whether a key is *spelled* the way a datamodel document declares it -
  that is `statifier_datamodel`'s question and not this skeleton's - and
  whether a screen the block document names exists at all, which
  `screens/1` answers as a separate finding rather than folding into
  either uniqueness rule.
  """

  alias StatifierBlocks.{Block, Document}
  alias StatifierExamples.Signup.Screens

  @screen_type "myapp.screen"

  @typedoc """
  One thing wrong with a Path.

  `:unknown_screen` names a `myapp.screen` block whose `screen` param is
  not a key in the element document. `:duplicate_element_key` and
  `:duplicate_outcome` each name the repeated name and every **block** that
  reaches it, in the order the Path visits them.

  The blocks are what is named, rather than the screens, because two of
  them may be one screen: a Path that shows a screen twice reaches its keys
  twice, and the second visit overwrites what the first one collected. That
  is the same hazard as two screens sharing a key and it is reported the
  same way - which a finding naming screens could not do, both visits
  having the same screen's name.
  """
  @type finding ::
          {:unknown_screen, block_id :: String.t(), screen_key :: String.t()}
          | {:duplicate_element_key, key :: String.t(), block_ids :: [String.t()]}
          | {:duplicate_outcome, outcome :: String.t(), block_ids :: [String.t()]}

  @doc """
  The screen keys `document`'s `myapp.screen` blocks name, in document
  order, with the block id each came from.

  Duplicated keys are kept: a Path that shows one screen twice is a Path
  this reports on rather than one it quietly de-duplicates.
  """
  @spec screen_refs(Document.t()) :: [{String.t(), String.t()}]
  def screen_refs(%Document{} = document) do
    for %Block{type: @screen_type, id: id, config: config} <- Document.blocks(document),
        do: {id, Map.get(config, "screen", "")}
  end

  @doc """
  Every finding about `document` as a Path, or `[]`.

  ## Examples

      iex> document = StatifierExamples.Signup.Path.document()
      iex> StatifierExamples.Signup.Path.validate(document)
      []
  """
  @spec validate(Document.t()) :: [finding()]
  def validate(%Document{} = document) do
    refs = screen_refs(document)
    {known, unknown} = Enum.split_with(refs, fn {_id, key} -> Screens.screen(key) end)

    Enum.map(unknown, fn {id, key} -> {:unknown_screen, id, key} end) ++
      duplicates(known, :duplicate_element_key, &Screens.answer_keys/1) ++
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
