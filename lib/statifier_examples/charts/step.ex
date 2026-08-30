defmodule StatifierExamples.Charts.Step do
  @moduledoc """
  The shape every example step in this app shares: a leaf block type that
  **names** one host invoke type and compiles to a call the host answers.

  This is the app's **one** step helper. Both example domains route through
  it - card processing, the signup wizard, and the shared messaging type -
  because a reference embedder that showed two ways to write the same step
  would be teaching the reader to pick, and there is nothing here to pick
  between. It lives under `StatifierExamples.Charts` for the reason the
  palette and the fixture list do: that is the seam the domains meet in,
  and a helper both domains need is not one domain's to own.

  This is host plumbing, not a block type. `statifier_blocks` owns the
  `StatifierBlocks.BlockType` behaviour and this module implements none of
  it; what it holds is the handful of decisions the example domains make
  the same way every time, factored out so twelve modules do not spell them
  twelve times:

    * the `invoke_type` config field every step carries, and the
      `myapp:*` grammar it has to be in;
    * the two outcomes a call has, `done` and `error`;
    * the emission - an `<invoke>` in an inner state, one transition per
      outcome, one `<final>` per outcome, with whatever `<param>` children
      the calling type wants - modelled on `StatifierBlocks.Core.Invoke`;
    * the palette-entry defaults, including the one accent token the
      example CSS declares.

  The two-registry seam matters here and is easy to lose: a block type
  **names** an invoke type, it never runs one. What runs is a handler the
  host registers separately, per session. This app's three handler modules
  - `StatifierExamples.CardAuth.Handlers`,
  `StatifierExamples.Signup.Handlers` and
  `StatifierExamples.Charts.Messaging.Handlers` - are written in one shape:
  `invoke_types/0` answers every name the module registers and `handle/2`
  answers one call. `StatifierExamples.Charts.invoke_types/0` is their
  union, and it is what the compiler reads as `:known_invoke_types`.

  Every function here is pure, because `StatifierBlocks.BlockType`'s purity
  rule (ADR-0002 decision 4) reaches anything a callback calls and not only
  the callback itself.
  """

  alias StatifierBlocks.Block
  alias StatifierBlocks.BlockType
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.Emit
  alias StatifierBlocks.Emission

  @invoke_type ~r/\Amyapp:[a-z][a-z0-9_]*\z/
  @identifier ~r/\A[a-z][a-z0-9_]*\z/

  # The custom property the example stylesheet declares for the host's
  # block accent. A name, never a colour: what it resolves to is a theme's
  # business, and `se-06z` declares it.
  @accent_token "--sb-accent-myapp"

  @done_event "done.invoke"
  @error_event "error.communication.invoke"

  @invoke_type_message ~s(must look like "myapp:capture")

  @doc """
  The two ways a call can finish, in the order they compile in.

  Declaration order is read by ADR-0004 decision 6's byte determinism, so
  this list is never sorted.
  """
  @spec outcomes() :: [BlockType.outcome_decl()]
  def outcomes, do: [{"done", "Done"}, {"error", "Error"}]

  @doc """
  This app's accent-token name, for a palette entry that wants it without
  reaching for the module attribute.
  """
  @spec accent_token() :: String.t()
  def accent_token, do: @accent_token

  @doc """
  The `invoke_type` field, declared with the step's own invoke type as its
  default.

  It is `required?: true` with a default for `core.on_event`'s reason: the
  field is one an author must answer, and the answer is prefilled with the
  only one that is usually right.
  """
  @spec invoke_type_field(String.t()) :: BlockType.field_decl()
  def invoke_type_field(default) when is_binary(default) do
    %{
      key: "invoke_type",
      type: :string,
      label: "Invoke type",
      required?: true,
      default: default
    }
  end

  @doc """
  The optional `label` field: the name this particular step goes by on the
  card, above the block type's own label.

  `statifier_blocks` titles a card from a declared `:string` field keyed
  `"label"` and demotes the palette label to the subtitle
  (`StatifierBlocks.ViewModel.title/1` and `subtitle/1`). Declaring it is
  the whole of what a host does to opt in - the fixtures have carried
  `config["label"]` since they were ported from the spike, and without the
  declaration nothing read them.

  It is `required?: false` with an empty default, the package's spelling
  for an optional string: a step that names nothing is titled by its type,
  which is the `core.*` vocabulary's own state.
  """
  @spec label_field() :: BlockType.field_decl()
  def label_field do
    %{
      key: "label",
      type: :string,
      label: "Label",
      required?: false,
      default: ""
    }
  end

  @doc """
  `label` first, then `invoke_type`, then whatever else the step declares.

  `label` leads because it is the field an author reaches for first - it is
  what the card says - and the inspector renders declaration order.
  """
  @spec config_schema(String.t(), [BlockType.field_decl()]) :: [BlockType.field_decl()]
  def config_schema(default, extra \\ []) when is_binary(default) and is_list(extra) do
    [label_field(), invoke_type_field(default) | extra]
  end

  @doc """
  The invoke type this config names: what it stored, or the step's own
  default when it stored nothing.

  A step whose config omits the key is naming its own invoke type, which
  is what the declared default says. That is not laxity: the alternative
  is a document that cannot say "the usual handler" without repeating it,
  and the field's default is the one place the usual handler is written
  down.
  """
  @spec invoke_type(Block.config(), String.t()) :: String.t()
  def invoke_type(config, default) when is_map(config) and is_binary(default) do
    case Map.get(config, "invoke_type") do
      nil -> default
      stored -> stored
    end
  end

  @doc """
  Checks a stored `invoke_type`, and passes an absent one - see
  `invoke_type/2` for why absence is an answer rather than a gap.
  """
  @spec check_invoke_type([BlockType.finding()], Block.config()) :: [BlockType.finding()]
  def check_invoke_type(findings, config) when is_list(findings) and is_map(config) do
    case Map.get(config, "invoke_type") do
      nil -> findings
      stored -> check_stored_invoke_type(findings, stored)
    end
  end

  @spec check_stored_invoke_type([BlockType.finding()], term()) :: [BlockType.finding()]
  defp check_stored_invoke_type(findings, stored) do
    if invoke_type?(stored) do
      findings
    else
      [{"invoke_type", @invoke_type_message} | findings]
    end
  end

  @doc """
  Checks that `key` holds a bare lowercase identifier, the check the
  spike's `queue` and `template` fields both spell.
  """
  @spec check_identifier([BlockType.finding()], Block.config(), String.t(), String.t()) ::
          [BlockType.finding()]
  def check_identifier(findings, config, key, message) do
    if identifier?(Map.get(config, key)) do
      findings
    else
      [{key, message} | findings]
    end
  end

  @doc """
  Turns an accumulated finding list into `validate_config/1`'s return,
  restoring the order the checks ran in.
  """
  @spec verdict([BlockType.finding()]) :: :ok | {:error, [BlockType.finding()]}
  def verdict([]), do: :ok
  def verdict(findings), do: {:error, Enum.reverse(findings)}

  @doc """
  Whether `value` is in the `myapp:*` invoke-type grammar the firewall
  fixes for this app's examples.
  """
  @spec invoke_type?(term()) :: boolean()
  def invoke_type?(value), do: non_empty_string?(value) and Regex.match?(@invoke_type, value)

  @doc "Whether `value` is a bare lowercase identifier."
  @spec identifier?(term()) :: boolean()
  def identifier?(value), do: non_empty_string?(value) and Regex.match?(@identifier, value)

  @spec non_empty_string?(term()) :: boolean()
  defp non_empty_string?(value) when is_binary(value) and value != "", do: String.valid?(value)
  defp non_empty_string?(_value), do: false

  @doc """
  A palette entry with this app's shared presentation defaults filled in.

  The defaults are the ones every example step in this app shares - the
  host accent token, and no keywords. `group` is deliberately not among
  them: which heading a step files under is the domain's fact, and a
  shared default would quietly file a signup step under card processing.

  `attrs` wins over every default, so a step pointing at its own accent
  token says so and is believed.
  """
  @spec palette_entry(BlockType.palette_entry()) :: BlockType.palette_entry()
  def palette_entry(attrs) when is_map(attrs) do
    Map.merge(%{accent_token: @accent_token, keywords: []}, attrs)
  end

  @doc """
  A step constrains nothing beyond being a step unless it says otherwise.
  """
  @spec io() :: StatifierBlocks.Assignability.io()
  def io, do: %{kinds: [:step]}

  @doc """
  A `<param>` carrying a literal, for a value the block type stores rather
  than reads out of the datamodel.

  `config_key` is stamped on the emission as the provenance of the value,
  so a finding inside it points at the author's field and not at this
  module.
  """
  @spec literal_param(String.t(), String.t(), String.t()) :: Emission.t()
  def literal_param(name, value, config_key)
      when is_binary(name) and is_binary(value) and is_binary(config_key) do
    "param"
    |> Emission.element([{"expr", "'" <> value <> "'"}, {"name", name}])
    |> Emission.from_config(config_key)
  end

  @doc """
  A compound state that calls the host and finishes at the `<final>` of
  whichever outcome the call reached.

      <state id="s_blk_RCP" initial="s_blk_RCP__running">
        <state id="s_blk_RCP__running">
          <invoke type="myapp:receipt"/>
          <transition event="done.invoke" target="s_blk_RCP__o_done"/>
          <transition event="error.communication.invoke" target="s_blk_RCP__o_error"/>
        </state>
        <final id="s_blk_RCP__o_done">
          <onentry><raise event="done.outcome.s_blk_RCP.done"/></onentry>
        </final>
        <final id="s_blk_RCP__o_error">
          <onentry><raise event="done.outcome.s_blk_RCP.error"/></onentry>
        </final>
      </state>

  This is `StatifierBlocks.Core.Invoke`'s shape with the `on_error` slot
  taken out: an example step has no children, so the failure path is an
  outcome a parent may wire rather than a subtree the block runs. Both
  transitions match by SCXML's descriptor prefix rule and neither names an
  invocation id, which is safe for the reason `core.invoke` gives - they
  sit on the inner state, active only while this block's own call is
  outstanding.

  The `type` attribute is stamped as coming from `invoke_type` only when
  the author actually wrote one. A step running on the declared default
  has no config key for a finding to point at, and attributing the
  attribute to a key the document does not carry would send an author
  looking for text they never typed.

  `params` are the `<param>` children the calling type wants on the
  `<invoke>`, in the order it wants them - `literal_param/3` builds one.
  A step with nothing to send omits the argument.
  """
  @spec emit(Block.t(), Context.t(), String.t(), [Emission.t()]) ::
          {:ok, Emission.t()} | {:error, BlockType.emit_error()}
  def emit(block, context, default, params \\ [])

  def emit(%Block{config: config}, %Context{} = context, default, params)
      when is_binary(default) and is_list(params) do
    with {:ok, running} <- Context.role_id(context, "running"),
         {:ok, done_final} <- Context.outcome_id(context, "done"),
         {:ok, error_final} <- Context.outcome_id(context, "error"),
         {:ok, invoke_type} <- checked_invoke_type(config, default) do
      inner =
        Emit.state(running, nil, [
          call(config, invoke_type, params),
          Emit.transition(event: @done_event, target: done_final),
          Emit.transition(event: @error_event, target: error_final)
        ])

      {:ok,
       Emit.state(context.state_id, running, [
         inner,
         Emit.final(done_final),
         Emit.final(error_final)
       ])}
    end
  end

  @spec call(Block.config(), String.t(), [Emission.t()]) :: Emission.t()
  defp call(config, invoke_type, params) do
    element = Emission.element("invoke", [{"type", invoke_type}], params)

    case Map.get(config, "invoke_type") do
      nil -> element
      _authored -> Emission.attribute_from_config(element, "type", "invoke_type")
    end
  end

  @spec checked_invoke_type(Block.config(), String.t()) ::
          {:ok, String.t()} | {:error, [BlockType.finding()]}
  defp checked_invoke_type(config, default) do
    invoke_type = invoke_type(config, default)

    if invoke_type?(invoke_type) do
      {:ok, invoke_type}
    else
      {:error, [{"invoke_type", @invoke_type_message}]}
    end
  end
end
