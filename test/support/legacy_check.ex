defmodule StatifierExamples.Test.LegacyCheck do
  @moduledoc """
  A stand-in for `myapp.legacy_check`, the one block type the app
  deliberately does not register.

  It exists for exactly one test: compiling the card-processing fixture
  against a palette that *does* resolve every type, so "the rest of the
  document is clean" is asserted rather than assumed. The compiler reports
  errors from the first failing stage only, so with the real palette the
  unresolvable block masks everything downstream of it - which is why the
  masked half needs a palette of its own to be seen at all.

  It lives in `test/support` and is never part of
  `StatifierExamples.Charts.palette/0`. Registering it there would delete
  the ADR-0005 decision 12 case the fixture is built around.
  """

  @behaviour StatifierBlocks.BlockType

  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.Emit

  @impl true
  def current_version, do: 3

  @impl true
  def slots(_config), do: []

  @impl true
  def config_schema(_config), do: []

  @impl true
  def validate_config(_config), do: :ok

  @impl true
  def io(_config), do: %{kinds: [:step]}

  @impl true
  def emit(_block, context) do
    done = Context.done_id(context)

    {:ok, Emit.state(context.state_id, done, [Emit.final(done)])}
  end
end
