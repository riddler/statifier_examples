defmodule StatifierExamples.CardAuth.Authorize do
  @moduledoc """
  `myapp.authorize`: authorizes the transaction against the card network.

  A leaf step naming the `myapp:authorize` handler, with the decision it
  writes and an optional call timeout. It runs nothing itself:
  `StatifierExamples.CardAuth.Handlers` is what this app registers to
  answer the call.

  ## Why this type is at version 2

  Version 1 spelled the target key `field` and version 2 spells it
  `assign_to`, so this is the app's one worked example of
  `c:StatifierBlocks.BlockType.migrate_config/2`. Migration runs at
  resolution time, in memory, and is never written back to the stored
  document (ADR-0002 decision 8) - a v1 block keeps its v1 bytes on disk
  and compiles as a v2 one.
  """

  alias StatifierBlocks.Core.Duration
  alias StatifierBlocks.InvokeStep
  alias StatifierExamples.Charts.Step

  @assign_to_message "must be a bare lowercase identifier, like authorization"
  @timeout_message "must be a duration - 30s or 1h30m - or ISO-8601 like PT30S"

  use StatifierBlocks.InvokeStep,
    invoke_type: "myapp:authorize",
    produces: "myapp.authorization",
    fields: [
      %{
        key: "assign_to",
        type: :string,
        label: "Write the decision to",
        required?: true,
        default: "authorization",
        datamodel_path?: true
      },
      %{
        key: "timeout",
        type: :duration,
        label: "Timeout",
        required?: false,
        default: "30s"
      }
    ],
    palette: %{
      label: "Authorize card",
      group: "Card processing",
      description: "Authorizes the transaction against the card network.",
      icon: "credit-card",
      keywords: ["authorize", "card", "payment"],
      order: 0,
      accent_token: Step.accent_token()
    }

  @impl StatifierBlocks.BlockType
  def current_version, do: 2

  @doc """
  The base's `invoke_type` check, plus this type's two.

  `assign_to` goes through `check_identifier/4` rather than the base's
  `check_assign_to/2`, which passes a blank: a card decision nobody keeps
  is not a decision, so this type declares the field required and refuses
  the blank.
  """
  @impl StatifierBlocks.BlockType
  def validate_config(config) do
    []
    |> InvokeStep.check_invoke_type(config)
    |> InvokeStep.check_identifier(config, "assign_to", @assign_to_message)
    |> check_timeout(config)
    |> InvokeStep.verdict()
  end

  # An absent `timeout` is read through the declared default rather than
  # refused, which is `core.parallel`'s reading of its own optional
  # `complete`. A stored `null` is not an absent key: it reaches the check
  # and is refused, as ADR-0001 decision 6 says it should be.
  @spec check_timeout([{String.t(), String.t()}], map()) :: [{String.t(), String.t()}]
  defp check_timeout(findings, config) do
    case Map.fetch(config, "timeout") do
      :error -> findings
      {:ok, timeout} -> check_stored_timeout(findings, timeout)
    end
  end

  @spec check_stored_timeout([{String.t(), String.t()}], term()) :: [{String.t(), String.t()}]
  defp check_stored_timeout(findings, timeout) do
    if Duration.duration?(timeout) do
      findings
    else
      [{"timeout", @timeout_message} | findings]
    end
  end

  @doc """
  The single hop from version 1's `field` to version 2's `assign_to`.

  A v1 config that carried no `field` at all migrates to the declared
  default rather than to an empty key: the field was required then too, so
  a document missing it was already invalid, and inventing an empty
  `assign_to` would turn an old document's authoring error into a new
  one's compile error at a key the author never wrote.
  """
  @impl StatifierBlocks.BlockType
  def migrate_config(1, config) do
    {field, rest} = Map.pop(config, "field")

    {:ok, Map.put(rest, "assign_to", field || "authorization")}
  end

  def migrate_config(from, _config), do: {:error, {:no_migration_from, from}}
end
