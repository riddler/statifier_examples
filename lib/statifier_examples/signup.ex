defmodule StatifierExamples.Signup do
  @moduledoc """
  The signup-wizard example domain: its block types, their invoke handlers,
  and the two documents that exercise them.

  The wizard is the second of the family's two canonical example domains,
  and it carries the A/B testing example. It models no real product: every
  address is `@example.com` and every name and amount is made up.

  Two block types, both of them a call to a host handler with an outcome:
  `myapp.signup_step` collects one step of the wizard and `myapp.provision`
  creates the workspace at the end of it. Everything else the two fixture
  documents are made of - the sequencing, the branch on the chosen plan, the
  interrupt rails, the child chart - is `statifier_blocks`' own `core.*`
  vocabulary, which is the division of labour this app exists to
  demonstrate: a host adds the steps its product has, and nothing else.
  """

  alias StatifierBlocks.{Decode, Document}
  alias StatifierExamples.Signup.{Provision, SignupStep}

  @typedoc """
  One example document, as `StatifierExamples.Charts.fixtures/0` lists it.

  `key` is URL-safe and stable - it is what a page puts in a path - and
  `name` is the document's own `metadata["name"]` rather than a second
  spelling of it that could drift.
  """
  @type fixture :: %{
          key: String.t(),
          name: String.t(),
          path: Path.t(),
          document: Document.t()
        }

  # `{key, file}`. Listed rather than globbed: which documents this app ships
  # is a fact worth reading in the source, and a stray file in `priv/` should
  # not silently become an example.
  @documents [
    {"signup_wizard", "signup_wizard.json"},
    {"signup_invitations", "signup_invitations.json"}
  ]

  @doc """
  The signup-wizard block types, as a `type_name => module` map suitable for
  `StatifierBlocks.Palette.new/2`.

  The name is the host's fact rather than the module's, which is what lets
  one module serve two names in two tenants' palettes (ADR-0002 decision 1).
  """
  @spec block_types() :: %{optional(String.t()) => module()}
  def block_types,
    do: %{
      "myapp.signup_step" => SignupStep,
      "myapp.provision" => Provision
    }

  @doc """
  The signup domain's example documents, decoded, in the order a page should
  offer them.

  Read from `priv/fixtures/` on every call rather than embedded at compile
  time: these are a handful of small files, and a fixture that can be edited
  and reloaded is worth more to an example app than the microseconds.
  """
  @spec fixtures() :: [fixture()]
  def fixtures, do: Enum.map(@documents, &load/1)

  @spec load({String.t(), String.t()}) :: fixture()
  defp load({key, file}) do
    path = Path.join([Application.app_dir(:statifier_examples), "priv", "fixtures", file])
    document = decode!(path)

    %{
      key: key,
      name: Map.get(document.metadata, "name", key),
      path: path,
      document: document
    }
  end

  # A shipped fixture that does not decode is a broken build, not a runtime
  # condition a caller could do anything about, so this raises rather than
  # answering an error tuple nobody would have a branch for. The test suite
  # is what keeps it from ever happening.
  @spec decode!(Path.t()) :: Document.t()
  defp decode!(path) do
    case Decode.decode(File.read!(path)) do
      {:ok, document} -> document
      {:error, error} -> raise "#{path} is not a block document: #{inspect(error)}"
    end
  end
end
