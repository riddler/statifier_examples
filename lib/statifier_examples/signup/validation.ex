defmodule StatifierExamples.Signup.Validation do
  @moduledoc """
  Whether what a screen collected is good enough to send: the pure check
  `StatifierExamples.Signup.Journey` runs before it raises a button's
  outcome.

  It stands in for the elements package Riddler R10c puts this in, and it
  is deliberately a **function over resolved nodes**, not a schema and not
  a changeset. The element document already says which questions a screen
  asks and what each one demands; a second declaration of the same rules
  somewhere else would be a second place for them to drift, which is the
  argument `StatifierExamples.Signup.Screen` makes about buttons.

  ## It checks what is on the screen, not what is in the document

  The nodes it takes are `StatifierExamples.Signup.Screens.resolve/2`'s
  output - conditions already evaluated - so a `required` question whose
  condition hides it is not checked. That is the only defensible reading:
  the confirm screen's referral question is required-shaped and only
  appears for a business plan, and a check over the raw document would
  refuse a personal signup for not answering a question it never saw.

  ## The two rules, and what a third would cost

  `required` is the document's own boolean. `format` is a named check this
  module implements, and today the only name is `email`; a name it does not
  implement **raises**, for `StatifierExamplesWeb.SignupElements`' reason
  about an unknown element type - a document asking for a check nobody runs
  is a document that silently accepts anything, which is worse than a page
  that will not draw.

  The email rule is one regex and it is not RFC 5322. It rejects what a
  reader would call a typo - no `@`, nothing before or after it, no dot in
  the domain - and nothing more, because the only check that really answers
  "is this address real" is sending mail to it, which the confirm screen's
  own paragraph says this wizard does.

  ## A finding is a pair, and the key is the element key

  `{key, message}` - the same key the answer lands at (`answers.<key>`,
  Riddler R10d), so a page can put the message beside the input it belongs
  to without a second lookup, and the order is the document's.
  """

  alias StatifierExamples.Signup.Screens

  @typedoc """
  One reason a screen cannot be submitted: the element key of the question
  at fault, and what to tell the reader about it.
  """
  @type finding :: {key :: String.t(), message :: String.t()}

  # Something before the @, something after it, and a dot in what follows.
  # See the moduledoc on why it is not more than that.
  @email ~r/\A[^\s@]+@[^\s@.]+\.[^\s@]+\z/

  @doc """
  Every reason `nodes` cannot be submitted with `answers`, in document
  order, or `[]`.

  `nodes` are resolved nodes - `StatifierExamples.Signup.Screens.resolve/2`'s
  answer - and `answers` is keyed by element key, as a form posts it.

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
  def validate(nodes, answers) when is_list(nodes) and is_map(answers) do
    for %{"type" => "text_question"} = question <- nodes,
        finding = check(question, Map.get(answers, Map.fetch!(question, "key"), "")),
        do: finding
  end

  # The first thing wrong with one answer, or `nil`. First rather than all,
  # because "is required" and "must look like an email address" about the
  # same empty box are one mistake told twice.
  @spec check(Screens.node_doc(), term()) :: finding() | nil
  defp check(question, answer) do
    key = Map.fetch!(question, "key")
    blank? = blank?(answer)

    cond do
      Map.get(question, "required") == true and blank? -> {key, "is required"}
      blank? -> nil
      true -> formatted(key, Map.get(question, "format"), answer)
    end
  end

  @spec formatted(String.t(), term(), term()) :: finding() | nil
  defp formatted(_key, nil, _answer), do: nil

  defp formatted(key, "email", answer) do
    if is_binary(answer) and Regex.match?(@email, answer) do
      nil
    else
      {key, "must look like an email address"}
    end
  end

  defp formatted(key, format, _answer) do
    raise ArgumentError,
          "no check for format #{inspect(format)} (question #{inspect(key)})"
  end

  # A number is never blank; a string of spaces always is.
  #
  # `StatifierExamples.Signup.Journey.submit/3` hands this module the form's
  # own strings and coerces afterwards, which is the right way round: a
  # digits-only answer becomes an integer for the payload and for re-resolving
  # the screen, but `required` and `format` are rules about what was **typed**
  # and a check that saw `5` where the reader wrote `5` has learned nothing
  # extra. So the string clauses are the ones `Journey` exercises. The
  # non-binary clause is for the other caller: `validate/2` is public, its
  # rules are about a screen rather than about a form, and a host holding
  # already-typed answers must not meet a crash here.
  @spec blank?(term()) :: boolean()
  defp blank?(answer) when is_binary(answer), do: String.trim(answer) == ""
  defp blank?(nil), do: true
  defp blank?(_answer), do: false
end
