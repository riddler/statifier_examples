defmodule StatifierExamplesWeb.SecretResponse do
  @moduledoc """
  What a page holds of a secret question's response between the keystroke
  and the press: the text the reader typed, in a struct that never shows
  it.

  A LiveView keeps its draft in its assigns, and a LiveView that crashes
  prints its whole state in the crash report - at debug, which is the level
  a dev server logs at. A secret question's typed text, a library card's
  PIN, held as a plain string would be printed there. Held in this struct
  it is printed as `#StatifierExamplesWeb.SecretResponse<redacted>`, by its
  `Inspect` implementation, wherever the draft is inspected: a crash
  report's state, a function's arguments in a stacktrace, a debug print.

  `reveal/1` takes the text back out, and the page calls it on the draft
  only as it hands the draft to `StatifierExamples.Signup.Journey.submit/4`,
  which seals the text before the chart is told anything.
  """

  @enforce_keys [:text]
  defstruct [:text]

  @typedoc "A secret question's typed text, held so it is never shown."
  @type t :: %__MODULE__{text: String.t()}

  @doc """
  The draft with every secret response's text in place of the struct, as
  `Journey.submit/4` takes it.

      iex> draft = %{"first_name" => "Rosa", "library_pin" => %StatifierExamplesWeb.SecretResponse{text: "0000"}}
      iex> StatifierExamplesWeb.SecretResponse.reveal(draft)
      %{"first_name" => "Rosa", "library_pin" => "0000"}

      iex> inspect(%StatifierExamplesWeb.SecretResponse{text: "0000"})
      "#StatifierExamplesWeb.SecretResponse<redacted>"
  """
  @spec reveal(map()) :: map()
  def reveal(draft) when is_map(draft) do
    Map.new(draft, fn
      {key, %__MODULE__{text: text}} -> {key, text}
      pair -> pair
    end)
  end

  defimpl Inspect do
    def inspect(_secret, _opts), do: "#StatifierExamplesWeb.SecretResponse<redacted>"
  end
end
