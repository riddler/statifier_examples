defmodule StatifierExamples.Signup.GuardedStep do
  @moduledoc """
  `myapp.guarded_step`: one call out, and a notification if it comes back on
  the error path.

  The second of the two **composites** this app ships as reference -
  `use StatifierBlocks.Composite`, params plus a pure `subtree/1` (sb
  ADR-0002 decision 5's amendment of 2026-09-07). The other is
  `StatifierExamples.CardAuth.AuthorizeWithDeadline`.

  It is the worked example sb ADR-0002 and ADR-0004 carry, written against
  this app's own vocabulary: a `core.invoke` with a `myapp.notify` in its
  `on_error` slot. Two params - which call to make, and which template to
  notify from - and the pairing of the two is the whole point. Wiring a
  handler to an error path is the step an author forgets, and a composite is
  how a host stops them having to remember.

  `myapp.notify` belongs to neither example domain
  (`StatifierExamples.Charts.Messaging` says why), which is what lets this
  composite live in the signup domain and still notify the way the
  card-processing documents do.

  ## Where it records its answer

  At `signup.step_outcome`, written here rather than taken as a param. Where
  a guarded call in this domain records what it got back is a fact about the
  arrangement, the same kind of fact as the notify on the error path; an
  author who wants to choose it wants the primitives, and the editor's
  Expand control hands them over.

  ## What it does not have

  No slot of its own (`RQ-SF037-3`). Expanding it in the editor replaces it
  with the two blocks `subtree/1` answers, and the compiled chart is
  byte-identical either way - which `StatifierExamples.CompositesTest`
  asserts.
  """

  use StatifierBlocks.Composite,
    name: "myapp.guarded_step",
    params: [
      %{
        key: "invoke_type",
        type: :string,
        label: "Call",
        required?: true,
        default: "myapp:provision"
      },
      %{
        key: "failure_template",
        type: :string,
        label: "Notify with",
        required?: true,
        default: "step_failed"
      }
    ],
    sentence: "Run {invoke_type}, notify on failure",
    palette_entry: %{
      label: "Guarded step",
      group: "Signup wizard",
      description: "One call, with a notification on the error path.",
      icon: "shield-check",
      keywords: ["guard", "invoke", "error", "notify"],
      order: 2
    },
    version: 1

  alias StatifierBlocks.Block

  # Where the call records what it answered. See the moduledoc: a fact about
  # the arrangement rather than a choice, and `signup` is the root every
  # document in this domain already declares.
  @outcome_path "signup.step_outcome"

  @doc """
  The call, and the notification on its error path.

  Pure, and the ids are local - `StatifierBlocks.Composite.expand/2` mints
  the document's ids from the composite block's own id.
  """
  @impl StatifierBlocks.Composite
  def subtree(params) do
    [
      Block.new("core.invoke",
        id: "call",
        config: %{
          "invoke_type" => params["invoke_type"],
          "assign_to" => @outcome_path,
          "params" => ""
        },
        slots: %{
          "on_error" => [
            Block.new("myapp.notify",
              id: "notify",
              config: %{
                "invoke_type" => "myapp:notify",
                "label" => "Notify on failure",
                "template" => params["failure_template"]
              }
            )
          ]
        }
      )
    ]
  end
end
