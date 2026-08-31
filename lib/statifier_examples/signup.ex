defmodule StatifierExamples.Signup do
  @moduledoc """
  The signup-wizard example domain: its block types, their invoke handlers,
  and the two documents that exercise them.

  The wizard is the second of the family's two canonical example domains,
  and it carries the A/B testing example. It models no real product: every
  address is `@example.com` and every name and amount is made up.

  Two block types, both of them a call to a host handler with an outcome:
  `myapp.signup_step` collects one step of the wizard and `myapp.provision`
  creates the workspace at the end of it. Everything else the three fixture
  documents are made of - the sequencing, the branch on the chosen plan, the
  interrupt rails, the child chart - is `statifier_blocks`' own `core.*`
  vocabulary, which is the division of labour this app exists to
  demonstrate: a host adds the steps its product has, and nothing else.

  `signup_onboarding` is the smallest of the three and exists for one
  reading: a parent chart that embeds the wizard as a `core.subchart` and
  routes on the outcome it finished with. It is deliberately one level
  deep - see `StatifierExamples.Charts.Subchart` on st-pvpz, and on what
  a durable run does with a subchart.
  """

  alias StatifierBlocks.{Block, Decode, Document, Edit}
  alias StatifierExamples.Charts.Fixture
  alias StatifierExamples.Signup.{Provision, SignupStep}

  @typedoc """
  One example document, as `StatifierExamples.Charts.fixtures/0` lists it.

  `key` is URL-safe and stable - it is what a page puts in a path - and
  `name` is the document's own `metadata["name"]` rather than a second
  spelling of it that could drift. `declare` is the `<data>` roots this
  *deployment* adds at compile time, over and above the ones the document
  declares for itself: see `StatifierExamples.Charts.Fixture`, which
  carries the reasoning and the same key.
  """
  @type fixture :: %{
          key: String.t(),
          name: String.t(),
          path: Path.t(),
          document: Document.t(),
          declare: [Fixture.declaration()]
        }

  # `{key, file, host-declared roots}`. Listed rather than globbed: which
  # documents this app ships is a fact worth reading in the source, and a
  # stray file in `priv/` should not silently become an example.
  #
  # Both lists are empty, and that is the point rather than an oversight.
  # The wizard used to declare `signup` here because a guard reading a root
  # nothing declared raises `error.execution` instead of reading it as
  # undefined - which is what used to send every run of it down the
  # `otherwise` arm - and a block document had nowhere to say so. It has
  # somewhere now: sb ADR-0001 decision 11 gives the envelope a `datamodel`
  # key, and each fixture declares its own roots in the bytes an author
  # edits and a reviewer diffs. This list is the other half, the
  # deployment's own additions, and this deployment adds none.
  @documents [
    {"signup_wizard", "signup_wizard.json", []},
    {"signup_invitations", "signup_invitations.json", []},
    {"signup_onboarding", "signup_onboarding.json", []}
  ]

  # The `core.send` whose delay is host configuration rather than a fact
  # about the chart, and the duration the fixture ships holding.
  @reminder_block "blk_su_reminder_timer"
  @default_reminder_delay "2d"

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

  @doc """
  How long an unverified signup waits before the wizard nudges it.

  Read from application config on every call, because it is the one thing
  about the reminder that a deployment gets to choose. A real product
  waits a day or two; a demo that waited two days would demonstrate
  nothing, and a chart edited down to ninety seconds would be a chart
  that lies about the product. So the fixture ships `#{@default_reminder_delay}`,
  a running app arms whatever this answers, and neither of them has to
  pretend to be the other.

  Any duration `StatifierBlocks.Core.Duration` accepts.
  """
  @spec reminder_delay() :: String.t()
  def reminder_delay do
    Application.get_env(:statifier_examples, :signup_reminder_delay, @default_reminder_delay)
  end

  @spec load({String.t(), String.t(), [Fixture.declaration()]}) :: fixture()
  defp load({key, file, declare}) do
    path = Path.join([Application.app_dir(:statifier_examples), "priv", "fixtures", file])
    document = path |> decode!() |> apply_reminder_delay()

    %{
      key: key,
      name: Map.get(document.metadata, "name", key),
      path: path,
      document: document,
      declare: declare
    }
  end

  # The configured delay, written onto the reminder block on the way out of
  # the loader, so every reader of a fixture - the editor page, the
  # compiler, a fired timer job rebuilding the chart - sees the same
  # document. It is an ordinary `:update_config` edit rather than a
  # rewrite of the JSON, so the document that reaches the canvas is one
  # the editor could itself have produced.
  #
  # It changes the document's bytes and therefore the content hash chart
  # identity is keyed on, which is the correct consequence and not a
  # side effect to design around: a run armed under one delay is a run of
  # a different chart from one armed under another, and the storage
  # layer's identity guard says so rather than resuming it quietly.
  #
  # A document with no reminder block - the invitations chart, and every
  # fixture the other domain ships - passes through untouched.
  @spec apply_reminder_delay(Document.t()) :: Document.t()
  defp apply_reminder_delay(%Document{} = document) do
    with %Block{config: config} <-
           Enum.find(Document.blocks(document), &(&1.id == @reminder_block)),
         config = Map.put(config, "delay", reminder_delay()),
         {:ok, edited, _inverse} <-
           Edit.apply(document, {:update_config, @reminder_block, config}) do
      edited
    else
      _absent_or_refused -> document
    end
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
