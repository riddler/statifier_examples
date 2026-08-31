defmodule StatifierExamples.CardAuth.Capture do
  @moduledoc """
  `myapp.capture`: captures a previously authorized amount.

  A leaf step naming the `myapp:capture` handler, with the datamodel key
  the amount is read from and how many times the host may retry. It runs
  nothing itself: `StatifierExamples.CardAuth.Handlers` is what this app
  registers to answer the call.

  The card-processing fixture uses this type inside the retry arm, where
  its block carries no `invoke_type` at all - the case
  `StatifierBlocks.InvokeStep.invoke_type/2` reads through the declared
  default.
  """

  alias StatifierBlocks.InvokeStep
  alias StatifierExamples.Charts.Step

  @amount_key_message "must be a bare lowercase identifier, like amount_cents"
  @retries_message "must be a whole number"

  use StatifierBlocks.InvokeStep,
    invoke_type: "myapp:capture",
    fields: [
      %{
        key: "amount_key",
        type: :string,
        label: "Amount read from",
        required?: true,
        default: "amount",
        datamodel_path?: true
      },
      %{
        key: "retries",
        type: :integer,
        label: "Retries",
        required?: false,
        default: 2
      }
    ],
    palette: %{
      label: "Capture funds",
      group: "Card processing",
      description: "Captures a previously authorized amount.",
      icon: "banknotes",
      keywords: ["capture", "settle", "payment"],
      order: 1,
      accent_token: Step.accent_token()
    }

  @doc """
  The base's `invoke_type` check, plus the two fields this type declares.
  """
  @impl StatifierBlocks.BlockType
  def validate_config(config) do
    []
    |> InvokeStep.check_invoke_type(config)
    |> InvokeStep.check_identifier(config, "amount_key", @amount_key_message)
    |> check_retries(config)
    |> InvokeStep.verdict()
  end

  # An absent `retries` reads through the declared default; a stored one
  # has to be a whole number, and `true` is not one - `is_integer/1` is
  # what separates them, since a boolean would otherwise pass any bounds
  # check written with comparison operators.
  @spec check_retries([{String.t(), String.t()}], map()) :: [{String.t(), String.t()}]
  defp check_retries(findings, config) do
    case Map.fetch(config, "retries") do
      :error -> findings
      {:ok, retries} when is_integer(retries) and retries >= 0 -> findings
      {:ok, _refused} -> [{"retries", @retries_message} | findings]
    end
  end

  @doc """
  What this step needs rather than what it produces: the base's
  `:produces` declaration has no room for a `consumes`, so the callback is
  written out here.
  """
  @impl StatifierBlocks.BlockType
  def io(_config), do: %{kinds: [:step], consumes: "myapp.authorization"}
end
