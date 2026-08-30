defmodule StatifierExamples.Signup.Step do
  @moduledoc """
  What the signup wizard's block types share: the `invoke_type` field every
  step declares, the check on it, and the emission that calls the host
  handler it names.

  This module is not itself a `StatifierBlocks.BlockType`. It is the host's
  own helper - the Elixir spelling of the spike's `step()` factory in
  `statifier_blocks`' `spike/js/demo-types.js` - and it exists for the
  reason that factory did: two block types that call one handler and finish
  the same two ways should have one description of what that means, not two
  that drift.

  ## Every step is an invoke with an outcome

  A block type **names** an invoke type and never runs one (ADR-0002
  decision 2). `emit/3` therefore compiles to the shape
  `StatifierBlocks.Core.Invoke` compiles to, minus its `on_error` slot: a
  compound state whose inner state holds the call, and one `<final>` per
  outcome. `done` when the handler answers, `error` when the call fails.

  The two transitions match `done.invoke` and `error.communication.invoke`
  by SCXML's descriptor prefix rule rather than naming the invocation, which
  is safe for `core.invoke`'s reason: both sit on the inner state, and that
  state is active only while this block's own call is outstanding.

  Unlike `core.invoke` this type declares no `on_error` slot, so the error
  outcome's `<final>` is always emitted. A parent that does not care which
  way the call went wires the `done.outcome.<state id>` prefix and never
  learns an outcome name.
  """

  alias StatifierBlocks.{Block, Emission}
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.Emit

  @typedoc "One `validate_config/1` finding: the config key, and author-facing text."
  @type finding :: {String.t(), String.t()}

  # The campaign's example namespace, and nothing else. A host that lets an
  # author type any `namespace:name` gets a chart naming a handler nobody
  # registered; this app ships two handlers and says so.
  @invoke_type ~r/\Amyapp:[a-z][a-z0-9_]*\z/

  @done_event "done.invoke"
  @error_event "error.communication.invoke"

  @outcomes [{"done", "Done"}, {"error", "Failed"}]

  @accent_token "--sb-accent-myapp"

  @doc """
  The accent token every block type in this app points at.

  A name, never a colour: the host declares an identity and the theme
  decides what it looks like (ADR-0002 amendment B, ADR-0005 decision 10).
  """
  @spec accent_token() :: String.t()
  def accent_token, do: @accent_token

  @doc """
  The ways a step can finish, in declaration order.

  Order is read by ADR-0004 decision 6's byte determinism and is never
  sorted.
  """
  @spec outcomes() :: [{String.t(), String.t()}]
  def outcomes, do: @outcomes

  @doc """
  The one config field every step carries: the host handler it names.

  `default` is the type's own invoke type rather than the empty string the
  spike used, so a step dragged out of the palette names a handler this app
  actually registers before an author touches it.
  """
  @spec invoke_type_field(String.t()) :: StatifierBlocks.BlockType.field_decl()
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
  Adds an `invoke_type` finding to `findings` unless `config` names one this
  app would recognise.
  """
  @spec check_invoke_type([finding()], Block.config()) :: [finding()]
  def check_invoke_type(findings, config) when is_list(findings) and is_map(config) do
    if invoke_type?(Map.get(config, "invoke_type")) do
      findings
    else
      [{"invoke_type", ~s(must look like "myapp:signup")} | findings]
    end
  end

  @doc """
  `:ok` for an empty finding list, `{:error, findings}` otherwise, with the
  findings back in the order they were checked in.
  """
  @spec verdict([finding()]) :: :ok | {:error, [finding()]}
  def verdict([]), do: :ok
  def verdict(findings) when is_list(findings), do: {:error, Enum.reverse(findings)}

  @doc """
  A `<param>` carrying a literal, for a value the block type stores rather
  than reads out of the datamodel.

  `config_key` is stamped on the emission as the provenance of the value, so
  a finding inside it points at the author's field and not at this module.
  """
  @spec literal_param(String.t(), String.t(), String.t()) :: Emission.t()
  def literal_param(name, value, config_key)
      when is_binary(name) and is_binary(value) and is_binary(config_key) do
    "param"
    |> Emission.element([{"expr", "'" <> value <> "'"}, {"name", name}])
    |> Emission.from_config(config_key)
  end

  @doc """
  The subtree a step compiles to: the call in an inner state, and a `<final>`
  for each of `outcomes/0`.

  `params` are the `<param>` children the calling type wants on the
  `<invoke>`, in the order it wants them.
  """
  @spec emit(Block.t(), Context.t(), [Emission.t()]) ::
          {:ok, Emission.t()} | {:error, StatifierBlocks.BlockType.emit_error()}
  def emit(%Block{config: config}, context, params) when is_list(params) do
    with {:ok, running} <- Context.role_id(context, "running"),
         {:ok, done_final} <- Context.outcome_id(context, "done"),
         {:ok, error_final} <- Context.outcome_id(context, "error"),
         {:ok, invoke_type} <- invoke_type(Map.get(config, "invoke_type")) do
      call =
        "invoke"
        |> Emission.element([{"type", invoke_type}], params)
        |> Emission.attribute_from_config("type", "invoke_type")

      inner =
        Emit.state(running, nil, [
          call,
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

  @spec invoke_type(term()) :: {:ok, String.t()} | {:error, [finding()]}
  defp invoke_type(value) do
    if invoke_type?(value) do
      {:ok, value}
    else
      {:error, [{"invoke_type", ~s(must look like "myapp:signup")}]}
    end
  end

  @spec invoke_type?(term()) :: boolean()
  defp invoke_type?(value),
    do: is_binary(value) and Regex.match?(@invoke_type, value)
end
