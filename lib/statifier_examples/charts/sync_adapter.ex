defmodule StatifierExamples.Charts.SyncAdapter do
  @moduledoc """
  The `Statifier.Invoke.Handler` this app's three synchronous domain
  handler modules are served by - `Statifier.Invoke.SyncHandler.Adapter`
  generated over the one handler list.

  ## Why the `use` moved out of `StatifierExamples.Charts`

  It lived there from se-4dt.2 until se-4dt.4, and moving it is not a
  retreat from that uptake: the engine still writes the adapter and this
  app still names its handlers once. What changed is that the app now
  registers a **second** kind of handler - the canonical
  `statifier_blocks:subchart` one, which is a full
  `Statifier.Invoke.Handler` rather than a sync call - and the two
  registrations a host declares therefore have two sources.
  `Statifier.Invoke.SyncHandler.Adapter` generates `invoke_types/0` and
  `invoke_handlers/0` as plain definitions over its own handler list, so a
  module that `use`s it cannot also state a union that includes something
  the list does not hold.

  So the generated pair stays exactly as the engine writes it, here, over
  the sync handlers alone, and `StatifierExamples.Charts` unions this
  module's answers with the subchart handler's. That keeps the engine's
  guarantee intact where it applies - the sync set the compiler lints
  against and the sync map a session dispatches on are still two readings
  of one list - and puts the app's own join one level up, where a reader
  can see both halves at once.

  A caller wanting the sync half alone comes here. Everything else in the
  app goes through `StatifierExamples.Charts`.
  """

  alias Statifier.Invoke.SyncHandler.Adapter
  alias StatifierExamples.{CardAuth, Signup}
  alias StatifierExamples.Charts.Messaging

  # The three domain handler modules, named once. `invoke_types/0`,
  # `invoke_handlers/0` and the `Statifier.Invoke.Handler` callbacks are all
  # generated over this list, and `StatifierExamples.Charts.dispatch/3`
  # reads it back as `sync_handlers/0`. A fourth domain's module joins here
  # and nowhere else.
  use Adapter, handlers: [CardAuth.Handlers, Messaging.Handlers, Signup.Handlers]
end
