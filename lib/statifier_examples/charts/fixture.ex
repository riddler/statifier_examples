defmodule StatifierExamples.Charts.Fixture do
  @moduledoc """
  One entry in `StatifierExamples.Charts.fixtures/0`: an example block
  document this app ships, decoded and ready to hand to the editor.

  The entry shape is this app's own choice, and it is five keys:

  | Key | What it is | Who reads it |
  |---|---|---|
  | `key` | a URL-safe name, unique across the app | `se-06z`'s DOCUMENT switcher, as `?doc=` |
  | `name` | the document's own `metadata["name"]` | the switcher's label |
  | `path` | where the JSON is on disk | a reader who wants the bytes |
  | `document` | the decoded `StatifierBlocks.Document` | the editor and the compiler |
  | `declare` | the `<data>` roots this chart's guards read | the compiler, as `:declare` |

  ## Why a fixture carries its own declared roots

  A block document cannot declare the datamodel roots its own guards read.
  `StatifierBlocks.Compiler.compile/3`'s `:declare` option is, in its own
  words, "the compile call's declaration surface and the only one", and a
  guard reading a root nothing declared raises `error.execution` rather
  than reading it as undefined - as does an assign writing to one. So a
  chart whose branch reads `signup.plan` only reaches the arm it guards
  when the **host** declares `signup`, and the host has to be told which
  roots those are.

  They are recorded per fixture, beside the chart whose guards read them,
  rather than in one app-wide list: which roots a chart needs is a fact
  about that chart, and a shared list would declare every name this app
  ever ships for every document it ever loads.

  A fixture whose guards read nothing declares nothing, which is why the
  key defaults to `[]` - and a document compiled with no declarations
  compiles to exactly the bytes it did before the key existed.

  `key` is what a URL carries, so it is a bare lowercase identifier and
  never derived from `name`: a title people rewrite would silently break
  every link that named it. `name` is read out of the document rather than
  spelled a second time here, so the two cannot drift.

  The fixtures are read and decoded on every call rather than embedded at
  compile time: they are a handful of small files, and one that can be
  edited and reloaded is worth more to an example app than the
  microseconds. A shipped fixture that does not decode raises - it is a
  broken build, not a condition a caller could branch on - and the suite is
  what keeps it from happening.

  `StatifierExamples.Signup` carries its own copy of this loader, written
  in parallel with this one. Converging the two is worth a follow-up bead;
  it is not worth rewriting a landed sibling's module from inside this one.
  """

  alias StatifierBlocks.Decode
  alias StatifierBlocks.Document

  @typedoc """
  One declared `<data>` root: an id, and either an initial expression
  written verbatim into the attribute or `nil` for a root that reads as
  undefined until something assigns it.

  The pair `StatifierBlocks.Compiler.compile/3` takes in its `:declare`
  list, spelled here so a fixture can be read without opening the
  compiler.
  """
  @type declaration :: {String.t(), String.t() | nil}

  @type t :: %{
          key: String.t(),
          name: String.t(),
          path: Path.t(),
          document: Document.t(),
          declare: [declaration()]
        }

  @doc """
  Reads and strictly decodes the fixture `file` under `priv/fixtures`, keys
  it as `key`, and records the `<data>` roots its guards read.

  `declare` defaults to `[]`: the shape of a chart that reads nothing out
  of a datamodel, which is most of them.
  """
  @spec load!(String.t(), String.t(), [declaration()]) :: t()
  def load!(key, file, declare \\ []) do
    path = Path.join([Application.app_dir(:statifier_examples), "priv", "fixtures", file])
    document = decode!(path)

    %{
      key: key,
      name: Map.get(document.metadata, "name", key),
      path: path,
      document: document,
      declare: declare
    }
  end

  @spec decode!(Path.t()) :: Document.t()
  defp decode!(path) do
    case Decode.decode(File.read!(path)) do
      {:ok, document} -> document
      {:error, error} -> raise "#{path} is not a block document: #{inspect(error)}"
    end
  end
end
