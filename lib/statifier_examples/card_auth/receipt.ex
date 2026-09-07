defmodule StatifierExamples.CardAuth.Receipt do
  @moduledoc """
  `myapp.receipt`: renders the receipt for the completed transaction.

  A leaf step naming the `myapp:receipt` handler and waiting for it to
  answer. It runs nothing itself: `StatifierExamples.CardAuth.Handlers` is
  what this app registers to answer the call.

  ## The one field, and the refusal it is here to show

  A receipt is a receipt *for* something settled, so this type reads a
  `cards.settlement` at the path its `settlement` field names. The field
  is a `{:path, %{expects: "cards.settlement"}}`, which under
  `statifier_blocks` ADR-0011 is a **read and not also a write**: it says
  what this step needs at that path and leaves nothing there.

  Pointed at `cards.settlement`, which is where the card-processing
  document's own receipt points it, the read is **satisfied** and says
  nothing further: that document declares the path AS the
  `cards.settlement` record, so what the environment holds there is
  exactly the record this field expects. No block in that flow writes a
  settlement and none has to - a declared path type is seeded from the
  document root forward, so the type is in hand from the first gap.

  Point the same field at the subject path - `cards.current_txn`, where
  intake left a `cards.credit_txn` - and it is **refused**, naming the
  path: a transaction is not a settlement, they are two declared records,
  and there is no widening between two records. That is the pair this
  example exists to show, and it is one field value apart: an author can
  produce both verdicts from the editor without touching any code.
  """

  alias StatifierBlocks.InvokeStep
  alias StatifierExamples.Charts.Step

  @settlement_message "must be a datamodel path, like cards.settlement"

  use StatifierBlocks.InvokeStep,
    invoke_type: "myapp:receipt",
    fields: [
      %{
        key: "settlement",
        type: {:path, %{expects: "cards.settlement"}},
        label: "Settlement read from",
        required?: false,
        default: "cards.settlement"
      }
    ],
    palette: %{
      label: "Receipt",
      group: "Card processing",
      description: "Renders the receipt for the completed transaction.",
      icon: "document-text",
      keywords: ["receipt", "summary", "document"],
      order: 8,
      accent_token: Step.accent_token()
    }

  @doc """
  The base's `invoke_type` check, plus the path this type reads.

  A blank is admitted - a receipt whose author has not said where the
  settlement is has not made a mistake yet, and the field is declared
  optional for the same reason - but a value that is there has to be a
  path rather than an expression or a sentence, because it is the key the
  environment is looked up under.
  """
  @impl StatifierBlocks.BlockType
  def validate_config(config) do
    []
    |> InvokeStep.check_invoke_type(config)
    |> check_settlement(config)
    |> InvokeStep.verdict()
  end

  @spec check_settlement([{String.t(), String.t()}], map()) :: [{String.t(), String.t()}]
  defp check_settlement(findings, config) do
    case Map.get(config, "settlement") do
      nil -> findings
      "" -> findings
      path when is_binary(path) -> path_finding(findings, path)
      _refused -> [{"settlement", @settlement_message} | findings]
    end
  end

  @spec path_finding([{String.t(), String.t()}], String.t()) :: [{String.t(), String.t()}]
  defp path_finding(findings, path) do
    if Regex.match?(~r/\A[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*\z/, path) do
      findings
    else
      [{"settlement", @settlement_message} | findings]
    end
  end
end
