defmodule StatifierExamples.Signup.GuardedSection do
  @moduledoc """
  `myapp.guarded_section`: a guarded call, and then a section of the author's
  own steps.

  The third **composite** this app ships as reference, and the first with a
  **pass-through slot** - `sb` ADR-0002's pass-through amendment of
  2026-09-07 (P1-P9), ADR-0004's (T1-T4) and ADR-0011's section 2. The other
  two are `StatifierExamples.CardAuth.AuthorizeWithDeadline` and
  `StatifierExamples.Signup.GuardedStep`, and neither exposes a slot.

  It is `GuardedStep` plus somewhere to put what comes next. The same two
  params - which call to make, and which template to notify from - the same
  `core.invoke` with a `myapp.notify` on its `on_error` path, and then a
  `core.group` whose `body` this composite exposes as its own slot named
  `body`, labelled "Then". An author drops blocks into that interior on the
  composite's own card; `StatifierBlocks.Composite.expand/2` splices them
  into the group, ids unchanged, and the compiled chart is byte-identical
  either way.

  ## The one thing a pass-through slot changes

  `slots/1` is `[{"body", :any, "Then"}]` rather than `[]`. Everything else
  a composite answers is what it answered before: `config_schema/1` is the
  params, `emit/2` raises, the expansion root is the subtree's head, and the
  ids of the members are minted from the composite block's own id. The
  author's children are **not** minted - they arrived carrying a document id
  already, which is what lets a block addressable only through the card
  before `Expand` be addressable in its own right, at the same id, after it.

  ## Why the mapped inner slot is `core.group`'s `body`

  The mapping is `%{name: "body", to: {"then", "body"}}`, and both halves are
  forced. `:to`'s first element is a **local id** of `subtree/1` - ADR-0002's
  P8 says so in as many words, and a minted `blk_*` id is refused by
  `check_local_ids!/2` - so it is `"then"`, the group's own local id. The
  inner slot is `"body"` because that is the slot `core.group` declares at
  `:any` arity and the one the subtree writes **empty**: P5's second and
  third refusals are that a mapped inner slot must be written by the subtree
  and must be written empty, because the author's children hold it and only
  them.

  It could not be the call's `on_error`. `core.invoke` declares exactly one
  slot (`lib/statifier_blocks/core/invoke.ex:96`) and this subtree fills it
  with the notification, which is P5's third refusal. A composite that wants
  a guarded call *and* somewhere to continue writes a second member, and
  that is what the group is.

  The record's own P8 writes the guarded call as `myapp.signup_step` with a
  `core.assign` on its `on_error`. This app's `myapp.signup_step` is a leaf
  `use StatifierBlocks.InvokeStep` whose `slots/1` is `[]`, so it has no
  `on_error` to write into; the arrangement here is the record's shape in
  the vocabulary this app actually has, which is the same substitution
  `statifier_blocks`' own `PassThroughTest` makes for the same reason.

  ## Where the call records its answer

  At `signup.step_outcome`, exactly as `GuardedStep` records it and for the
  same reason. It is what makes the walk observable: the environment a child
  of the `body` slot is read against holds `signup.step_outcome`, and the
  environment reaching the composite does not, because the entry is put by a
  member of the expansion and the walk descends at the mapped inner position
  (ADR-0011 section 2). `StatifierExamples.CompositesTest` asserts both.

  ## The same declaration, held as data

  `declaration/0` is this composite spelled as a `StatifierBlocks.Composite.Data`
  row - the P9 shape, with the declaration-level `"slots"` key. It is here
  rather than in the test so the two spellings sit in one file and a reader
  can diff them; the byte-identity of the two is asserted rather than
  assumed.
  """

  use StatifierBlocks.Composite,
    name: "myapp.guarded_section",
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
    slots: [%{name: "body", to: {"then", "body"}, label: "Then"}],
    sentence: "Run {invoke_type}, notify on failure, then continue",
    palette_entry: %{
      label: "Guarded section",
      group: "Signup wizard",
      description: "One call with a notification on the error path, and a section after it.",
      icon: "shield-check",
      keywords: ["guard", "invoke", "error", "notify", "section"],
      order: 3
    },
    version: 1

  alias StatifierBlocks.Block

  # The same path `StatifierExamples.Signup.GuardedStep` records at, and for
  # the reason its moduledoc gives: where a guarded call in this domain
  # records what it got back is a fact about the arrangement.
  @outcome_path "signup.step_outcome"

  @doc """
  The guarded call, and the group the author's own steps land in.

  Pure, and the ids are local. The group's `body` is written **empty** and
  its `interrupts` beside it, which is what makes the mapping legal: P5
  refuses a mapped inner slot the subtree does not write, and refuses one
  the subtree also fills.
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
      ),
      Block.new("core.group", id: "then", slots: %{"body" => [], "interrupts" => []})
    ]
  end

  @doc """
  The identical declaration, held as data: the row a host would have stored.

  ADR-0002's P9 shape. Three things differ from the `use` above and all
  three are spellings rather than decisions: the keys are strings, a
  placeholder is a `%{"$param" => key}` map where the module reads
  `params[key]`, and the sentence spells its placeholders `{{key}}` where
  the module spells them `{key}` (`StatifierBlocks.Composite.Data`'s own
  note: one vocabulary, two spellings, one renderer). The `"slots"` key here
  is the **declaration-level** one - a sibling of `"subtree"` - and the
  `"slots"` inside a subtree node is the node-level key that has always been
  there.

  The `"id_suffix"` of each node is the local id `subtree/1` writes, so the
  two kinds mint the same ids and are byte-identical in a document rather
  than merely equivalent.
  """
  @spec declaration() :: map()
  def declaration do
    %{
      "type_name" => "myapp.guarded_section",
      "version" => 1,
      "sentence" => "Run {{invoke_type}}, notify on failure, then continue",
      "palette_entry" => %{
        "label" => "Guarded section",
        "group" => "Signup wizard",
        "description" =>
          "One call with a notification on the error path, and a section after it.",
        "icon" => "shield-check",
        "keywords" => ["guard", "invoke", "error", "notify", "section"],
        "order" => 3
      },
      "params" => [
        %{
          "key" => "invoke_type",
          "type" => "string",
          "label" => "Call",
          "required?" => true,
          "default" => "myapp:provision"
        },
        %{
          "key" => "failure_template",
          "type" => "string",
          "label" => "Notify with",
          "required?" => true,
          "default" => "step_failed"
        }
      ],
      "slots" => %{"body" => %{"to" => ["then", "body"], "label" => "Then"}},
      "subtree" => [
        %{
          "type" => "core.invoke",
          "id_suffix" => "call",
          "config" => %{
            "invoke_type" => %{"$param" => "invoke_type"},
            "assign_to" => @outcome_path,
            "params" => ""
          },
          "slots" => %{
            "on_error" => [
              %{
                "type" => "myapp.notify",
                "id_suffix" => "notify",
                "config" => %{
                  "invoke_type" => "myapp:notify",
                  "label" => "Notify on failure",
                  "template" => %{"$param" => "failure_template"}
                }
              }
            ]
          }
        },
        %{
          "type" => "core.group",
          "id_suffix" => "then",
          "slots" => %{"body" => [], "interrupts" => []}
        }
      ]
    }
  end
end
