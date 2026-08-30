defmodule StatifierExamples.Charts.Fixture do
  @moduledoc """
  One entry in `StatifierExamples.Charts.fixtures/0`: an example block
  document this app ships, decoded and ready to hand to the editor.

  The entry shape is this app's own choice, and it is four keys:

  | Key | What it is | Who reads it |
  |---|---|---|
  | `key` | a URL-safe name, unique across the app | `se-06z`'s DOCUMENT switcher, as `?doc=` |
  | `name` | the document's own `metadata["name"]` | the switcher's label |
  | `path` | where the JSON is on disk | a reader who wants the bytes |
  | `document` | the decoded `StatifierBlocks.Document` | the editor and the compiler |

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

  @type t :: %{
          key: String.t(),
          name: String.t(),
          path: Path.t(),
          document: Document.t()
        }

  @doc """
  Reads and strictly decodes the fixture `file` under `priv/fixtures`, and
  keys it as `key`.
  """
  @spec load!(String.t(), String.t()) :: t()
  def load!(key, file) do
    path = Path.join([Application.app_dir(:statifier_examples), "priv", "fixtures", file])
    document = decode!(path)

    %{
      key: key,
      name: Map.get(document.metadata, "name", key),
      path: path,
      document: document
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
