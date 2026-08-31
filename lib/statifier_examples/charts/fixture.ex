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
  | `declare` | the `<data>` roots this **deployment** adds | the compiler, as `:declare` |

  ## Why a fixture carries a declare list at all

  A guard reading a root nothing declared raises `error.execution` rather
  than reading it as undefined - as does an assign writing to one - so a
  chart whose branch reads `signup.plan` only reaches the arm it guards
  when `signup` is declared somewhere. There are two somewheres, and sb
  ADR-0001 decision 11 is what put the second one there.

  The **document** declares the roots without which its own expressions
  are nonsense on every host, in its top-level `datamodel` key: a property
  of the tree an author edits, in the bytes the hash covers. Every fixture
  this app ships does that, which is why all three declare lists here are
  now empty.

  This key is the other half, the **deployment's**: roots a particular
  host seeds over and above what the document asks for. Decision 11f makes
  it lead - the compile call's roots come first in the emitted
  `<datamodel>`, the document's follow, and an id both surfaces name is
  host-wins with a `:shadowed_document_root` warning on the artifact.

  The list is recorded per fixture, beside the chart it is compiled with,
  rather than in one app-wide list: what a deployment adds is a fact about
  that pairing, and a shared list would declare every name this app ever
  ships for every document it ever loads.

  A fixture the deployment adds nothing for declares nothing, which is why
  the key defaults to `[]` - and a document compiled with no host
  declarations compiles to exactly the bytes it did before the option
  existed.

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
  it as `key`, and records the `<data>` roots this deployment adds.

  `declare` defaults to `[]`: the shape of a document that declares every
  root it reads for itself, which is all of them here.
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
