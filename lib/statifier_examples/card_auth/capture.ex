defmodule StatifierExamples.CardAuth.Capture do
  @moduledoc """
  `myapp.capture`: captures a previously authorized amount.

  A leaf step naming the `myapp:capture` handler, with the datamodel key
  the amount is read from and how many times the host may retry. It runs
  nothing itself: `StatifierExamples.CardAuth.Handlers` is what this app
  registers to answer the call.

  The card-processing fixture uses this type inside the retry arm, where
  its block carries no `invoke_type` at all - the case
  `StatifierExamples.Charts.Step.invoke_type/2` reads through the declared
  default.
  """

  @behaviour StatifierBlocks.BlockType

  alias StatifierExamples.Charts.Step

  @invoke_type "myapp:capture"

  @amount_key_message "must be a bare lowercase identifier, like amount_cents"
  @retries_message "must be a whole number"

  @doc "The invoke type this step names when its config does not say otherwise."
  @spec invoke_type() :: String.t()
  def invoke_type, do: @invoke_type

  @impl true
  def current_version, do: 1

  @impl true
  def slots(_config), do: []

  @impl true
  def config_schema(_config) do
    Step.config_schema(@invoke_type, [
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
    ])
  end

  @impl true
  def validate_config(config) do
    []
    |> Step.check_invoke_type(config)
    |> Step.check_identifier(config, "amount_key", @amount_key_message)
    |> check_retries(config)
    |> Step.verdict()
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

  @impl true
  def io(_config), do: %{kinds: [:step], consumes: "myapp.authorization"}

  @impl true
  def outcomes(_config), do: Step.outcomes()

  @impl true
  def palette_entry do
    Step.palette_entry(%{
      label: "Capture funds",
      group: "Card processing",
      description: "Captures a previously authorized amount.",
      icon: "banknotes",
      keywords: ["capture", "settle", "payment"],
      order: 1
    })
  end

  @impl true
  def emit(block, context), do: Step.emit(block, context, @invoke_type)
end
