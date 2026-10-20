defmodule StatifierExamples.Signup.Validation do
  @moduledoc """
  Whether what a screen collected is good enough to send: the pure check
  `StatifierExamples.Signup.Journey` runs before it raises a button's
  outcome.

  The rules are riddler's. `validate/2` hands the nodes and the responses to
  `Riddler.Screens.validate_screen/3` and turns each finding it answers into
  the pair a page puts beside an input. What it keeps of its own is the
  shape of its answer and the wording a reader sees, and it is deliberately
  a **function over resolved nodes**, not a schema and not a changeset. The
  element document already says which questions a screen asks and what each
  one demands; a second declaration of the same rules somewhere else would
  be a second place for them to drift, which is the argument
  `StatifierExamples.Signup.Screen` makes about buttons.

  ## It checks what is on the screen, not what is in the document

  The nodes it takes are `StatifierExamples.Signup.Screens.resolve/2`'s
  output - conditions already evaluated - so a `required` question whose
  condition hides it is not checked. Every node it is handed is checked: a
  `condition` still on one is dropped before riddler sees it, because the
  caller has already decided the node is on the screen.

  ## The rules, and the one this app keeps for itself

  `required` and `format` are what riddler checks a `text_question` for. A
  `required` that is not the boolean `true` requires nothing, a blank or
  absent response is not put to a format, and a question answers one
  finding however many of its rules it breaks.

  The one rule this module keeps is which formats a document may ask for.
  Riddler checks more than one, and this app has a reader-facing message
  for `email` alone, so a `text_question` naming any other format
  **raises**, for `StatifierExamplesWeb.SignupElements`' reason about an
  unknown element type: a check this app cannot explain to a reader is a
  screen that cannot be finished, which is worse than a page that will not
  draw.

  ## A finding is a pair, and the key is the element key

  `{key, message}` - the same key the response lands at (`responses.<key>`,
  ruled by the operator for Riddler, 2026-09-12), so a page can put the
  message beside the input it belongs to without a second lookup, and the
  order is the document's. The key is riddler's `node_key`; the message is
  this app's for the two codes a shipped screen can raise, and riddler's own
  for any other.
  """

  alias Riddler.Finding
  alias Riddler.Screens.Document
  alias StatifierExamples.Signup.Screens

  @typedoc """
  One reason a screen cannot be submitted: the element key of the question
  at fault, and what to tell the reader about it.
  """
  @type finding :: {key :: String.t(), message :: String.t()}

  # The formats this app has a message for. See the moduledoc.
  @formats ["email"]

  # The screen the nodes are wrapped in to reach riddler. Its key and title
  # are never shown and never read back.
  @screen_key "validated_screen"

  @doc """
  Every reason `nodes` cannot be submitted with `responses`, in document
  order, or `[]`.

  `nodes` are resolved nodes - `StatifierExamples.Signup.Screens.resolve/2`'s
  answer - and `responses` is keyed by element key, as a form posts it.

  ## Examples

      iex> nodes = [%{"type" => "text_question", "key" => "email",
      ...>            "required" => true, "format" => "email"}]
      iex> StatifierExamples.Signup.Validation.validate(nodes, %{"email" => ""})
      [{"email", "is required"}]
      iex> StatifierExamples.Signup.Validation.validate(nodes, %{"email" => "ada"})
      [{"email", "must look like an email address"}]
      iex> StatifierExamples.Signup.Validation.validate(nodes, %{"email" => "ada@example.com"})
      []
  """
  @spec validate([Screens.node_doc()], %{optional(String.t()) => term()}) :: [finding()]
  def validate(nodes, responses) when is_list(nodes) and is_map(responses) do
    Enum.each(nodes, &known_format!/1)

    document = admit!(nodes)

    case Riddler.Screens.validate_screen(document, @screen_key, %{"responses" => responses}) do
      :ok -> []
      {:error, findings} -> Enum.map(findings, &pair/1)
    end
  end

  @spec known_format!(Screens.node_doc()) :: :ok
  defp known_format!(%{"type" => "text_question"} = question) do
    case Map.get(question, "format") do
      nil ->
        :ok

      format when format in @formats ->
        :ok

      format ->
        raise ArgumentError,
              "no check for format #{inspect(format)} " <>
                "(question #{inspect(Map.get(question, "key"))})"
    end
  end

  defp known_format!(_not_a_text_question), do: :ok

  @spec admit!([Screens.node_doc()]) :: Document.t()
  defp admit!(nodes) do
    envelope = %{
      "schema_version" => 1,
      "id" => "edoc_validated",
      "screens" => [
        %{
          "key" => @screen_key,
          "title" => @screen_key,
          "nodes" => Enum.map(nodes, &Map.delete(&1, "condition"))
        }
      ]
    }

    case Document.admit(envelope) do
      nil -> raise ArgumentError, "the nodes are not ones riddler admits as a screen's"
      document -> document
    end
  end

  @spec pair(Finding.t()) :: finding()
  defp pair(%Finding{code: "response.required", node_key: key}), do: {key, "is required"}

  defp pair(%Finding{code: "response.format", node_key: key}),
    do: {key, "must look like an email address"}

  defp pair(%Finding{node_key: key, message: message}), do: {key, message}
end
