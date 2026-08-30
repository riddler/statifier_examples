defmodule StatifierExamples.Charts.Messaging do
  @moduledoc """
  The messaging vocabulary both example domains share: one block type,
  `myapp.notify`, and its handler.

  It sits under `StatifierExamples.Charts` rather than under either domain
  because it belongs to neither. A card-processing chart notifies when a
  validation fails or a receipt is ready; a signup wizard notifies when a
  step is abandoned. Filing it under one of them would make the other
  reach across a domain boundary for a step that is really host plumbing.
  """

  alias StatifierExamples.Charts.Messaging.Notify

  @block_types %{"myapp.notify" => Notify}

  @doc """
  The messaging block types, as a `type_name => module` map suitable for
  `StatifierBlocks.Palette.new/2`.
  """
  @spec block_types() :: %{optional(String.t()) => module()}
  def block_types, do: @block_types
end
