defmodule StatifierExamples.Signup do
  @moduledoc """
  The signup-wizard example domain: its block types and their invoke
  handlers.

  This module is a declared seam, not an implementation. Bead `se-5de` fills
  it with the signup-wizard block types (signup step, provision) and notify,
  their handlers, and the two signup fixture documents.

  The wizard is the second of the family's two canonical example domains,
  and it carries the A/B testing example. It models no real product: every
  address is `@example.com` and every name and amount is made up.
  """

  @doc """
  The signup-wizard block types, as a `type_name => module` map suitable for
  `StatifierBlocks.Palette.new/2`.

  Empty until `se-5de` registers the types.
  """
  @spec block_types() :: %{optional(String.t()) => module()}
  def block_types, do: %{}
end
