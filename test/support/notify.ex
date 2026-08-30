defmodule StatifierExamples.Support.Notify do
  @moduledoc """
  A test-only stand-in for `myapp.notify`, the messaging block type
  `StatifierExamples.Charts.Messaging` owns.

  `priv/fixtures/signup_wizard.json` names `myapp.notify` in the otherwise
  arm of its plan branch, so compiling that document needs the type in the
  palette. Messaging is not this bead's to write (`se-rrd` owns it), and
  waiting for it would leave the signup fixtures uncompiled by anything.

  This module is deliberately the smallest thing that resolves: it is not a
  second opinion about what `myapp.notify` should be, and it goes away the
  moment `Charts.palette/0` composes the real one.
  """

  @behaviour StatifierBlocks.BlockType

  alias StatifierExamples.Signup.Step

  @impl true
  def current_version, do: 1

  @impl true
  def slots(_config), do: []

  @impl true
  def config_schema(_config), do: [Step.invoke_type_field("myapp:notify")]

  @impl true
  def validate_config(config) do
    []
    |> Step.check_invoke_type(config)
    |> Step.verdict()
  end

  @impl true
  def outcomes(_config), do: Step.outcomes()

  @impl true
  def emit(block, context), do: Step.emit(block, context, [])
end
