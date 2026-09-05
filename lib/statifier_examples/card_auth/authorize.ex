defmodule StatifierExamples.CardAuth.Authorize do
  @moduledoc """
  `myapp.authorize`: authorizes the transaction against the card network.

  A leaf step naming the `myapp:authorize` handler and the decision it
  writes. It runs nothing itself:
  `StatifierExamples.CardAuth.Handlers` is what this app registers to
  answer the call.

  ## Why this type carries no deadline

  It used to declare an optional `timeout` duration, render it in the
  editor and validate it on save - and then drop it, because this type
  takes `StatifierBlocks.InvokeStep`'s default emit and never passed the
  value on. A control that invites an author to set a deadline, and a
  validator that confirms the value is well formed, while nothing
  enforces one, is worse than no control at all, and this app is the
  reference embedder: an inert field teaches the wrong shape.

  The field is gone rather than wired up, because a deadline on a call is
  not a property of the step in this vocabulary. `statifier_blocks`
  ADR-0010 records the spelling: a clock interrupt is the **pair** of a
  `core.send` carrying the deadline event and a `delay`, placed first in
  the enclosing group's `body` slot, and a `core.on_event` on that same
  group's `interrupts` rail naming the event with an `outcome`. The
  card-processing fixture authors its authorization deadline exactly that
  way, around this step rather than on it.

  ## Why this type is at version 2

  Version 1 spelled the target key `field` and version 2 spells it
  `assign_to`, so this is the app's one worked example of
  `c:StatifierBlocks.BlockType.migrate_config/2`. Migration runs at
  resolution time, in memory, and is never written back to the stored
  document (ADR-0002 decision 8) - a v1 block keeps its v1 bytes on disk
  and compiles as a v2 one.
  """

  alias StatifierBlocks.InvokeStep
  alias StatifierExamples.Charts.Step

  @assign_to_message "must be a bare lowercase identifier, like authorization"

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
  The base's `invoke_type` check, plus this type's own.

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
    |> InvokeStep.verdict()
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
