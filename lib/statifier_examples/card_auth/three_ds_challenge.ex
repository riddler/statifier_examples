defmodule StatifierExamples.CardAuth.ThreeDsChallenge do
  @moduledoc """
  `myapp.three_ds_challenge`: sends the cardholder a step-up authentication challenge.

  Stored at `type_version` 2 in this app's card-processing fixture, so
  the block resolves without migrating.

  A leaf step naming the `myapp:three_ds` handler and waiting for it to
  answer. It runs nothing itself: `StatifierExamples.CardAuth.Handlers` is
  what this app registers to answer the call.
  """

  alias StatifierExamples.Charts.Step

  use StatifierBlocks.InvokeStep,
    invoke_type: "myapp:three_ds",
    palette: %{
      label: "3-D Secure",
      group: "Card processing",
      description: "Sends the cardholder a step-up authentication challenge.",
      icon: "device-phone-mobile",
      keywords: ["3ds", "challenge", "step-up"],
      order: 5,
      accent_token: Step.accent_token()
    }

  @doc """
  Version 2 with no migration: the fixture stores this type at
  `type_version` 2 already, so no block of it has ever carried a version 1
  shape to migrate from. The injected `migrate_config/2` refuses every
  `from` it is asked about, which is the right answer for a type with no
  older shape.
  """
  @impl StatifierBlocks.BlockType
  def current_version, do: 2
end
