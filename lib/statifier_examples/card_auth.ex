defmodule StatifierExamples.CardAuth do
  @moduledoc """
  The card-processing example domain: its block types and their invoke
  handlers.

  This module is a declared seam, not an implementation. Bead `se-rrd` fills
  it with the block-type modules for the card-processing vocabulary
  (authorize card, intake, capture funds, risk rating, manual flag, balance
  check, 3-D secure, park, resolve review, receipt) and the handlers they
  invoke, together with the card-processing fixture document.

  The vocabulary is one of the family's two canonical example domains. It
  models no real payment processor: every value that appears in a fixture or
  a seed here is fictional.
  """

  @doc """
  The card-processing block types, as a `type_name => module` map suitable
  for `StatifierBlocks.Palette.new/2`.

  Empty until `se-rrd` registers the types.
  """
  @spec block_types() :: %{optional(String.t()) => module()}
  def block_types, do: %{}
end
