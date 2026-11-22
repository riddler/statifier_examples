defmodule StatifierExamples.Library.RegistrationSteps do
  @moduledoc """
  Patron registration in three steps, as a Journey a patron can go back in.

  Two documents, the block half and the element half of one Path:
  `priv/fixtures/patron_registration_steps.json` is a `core.sequence` of
  three `myapp.step` blocks (`StatifierExamples.Signup.ReturnableStep`),
  and `priv/fixtures/patron_registration_steps_screens.json` says what is
  on each of their screens - who the patron is, which card, which branch
  they collect holds from.

  It is the smallest document built from `myapp.step` that shows what a
  returnable step is for: on the card or the branch screen, Back takes the
  patron to the step before, with what they gave there still filled in.
  The signup Path cannot show it, because its screens are composites.

  It is not one of the fixtures `StatifierExamples.Charts.fixtures/0`
  lists. It is run as a supplied Path: `options/0` is what every
  `StatifierExamples.Signup.Journey` call over it takes, and
  `StatifierExamplesWeb.SignupJourneyLive` runs it under the key `key/0`.
  """

  alias StatifierBlocks.{Decode, Document}

  @key "patron_registration_steps"
  @path_file "patron_registration_steps.json"
  @screens_file "patron_registration_steps_screens.json"

  @doc "The key a page names this Path by."
  @spec key() :: String.t()
  def key, do: @key

  @doc "The Path: the block document of `myapp.step` blocks."
  @spec document() :: Document.t()
  def document do
    case Decode.decode(File.read!(fixture(@path_file))) do
      {:ok, document} -> document
      {:error, error} -> raise "#{@path_file} is not a block document: #{inspect(error)}"
    end
  end

  @doc "The screens document the Path's steps name, decoded."
  @spec screens() :: map()
  def screens, do: @screens_file |> fixture() |> File.read!() |> Jason.decode!()

  @doc """
  The options every `StatifierExamples.Signup.Journey` call over this Path
  takes: the screens document and the Path.
  """
  @spec options() :: [screens: map(), path: Document.t()]
  def options, do: [screens: screens(), path: document()]

  @spec fixture(String.t()) :: Path.t()
  defp fixture(file),
    do: Path.join([Application.app_dir(:statifier_examples), "priv", "fixtures", file])
end
