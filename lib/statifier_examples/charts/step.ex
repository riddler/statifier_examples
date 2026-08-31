defmodule StatifierExamples.Charts.Step do
  @moduledoc """
  What is left of this app's step helper once the shape moved upstream:
  one token name.

  Every example step in this app used to reach a local module for the
  `invoke_type` field grammar, the `done`/`error` outcomes, the emission
  and the palette defaults. `statifier_blocks` ADR-0007 makes that shape
  the package's own - `StatifierBlocks.InvokeStep` - so the twelve step
  types are declarations on it now and the three hundred lines that stood
  in for it here are gone.

  What did not move is the one decision that is genuinely this host's: the
  custom property the example stylesheet declares for the block accent.
  Upstream deliberately leaves `accent_token` out of its palette defaults,
  because which accent a host paints its own blocks with is not a fact the
  editor package can know. `se-06z` declares the property; this is where
  its name is written down once, so twelve palette entries do not spell it
  twelve times.

  The two-registry seam is unchanged and is still the thing easiest to
  lose: a block type **names** an invoke type, it never runs one. What
  runs is a handler the host registers separately, per session -
  `StatifierExamples.CardAuth.Handlers`,
  `StatifierExamples.Signup.Handlers` and
  `StatifierExamples.Charts.Messaging.Handlers`, whose union
  `StatifierExamples.Charts.invoke_types/0` is what the compiler reads as
  `:known_invoke_types`.
  """

  # A name, never a colour: what it resolves to is a theme's business.
  @accent_token "--sb-accent-myapp"

  @doc """
  This app's accent-token name, for the palette entry of every `myapp.*`
  step.
  """
  @spec accent_token() :: String.t()
  def accent_token, do: @accent_token
end
