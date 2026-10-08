defmodule StatifierExamples.FormPost.CheckServiceArea do
  @moduledoc """
  The card application's service-area check, the
  `myapp:check_service_area` step: handed an application's id, it answers
  `"inside"` or `"outside"`.

  The rule is a teaching rule over a made-up town: an address on one of a
  handful of Riverbend streets is inside the library's service area, and
  any other address is outside. A host's real check sits where `area/1`
  does, perhaps calling a geocoder, reads the address through the same
  reader, and answers a word the chart's conditions can read.

  The answer is the word and nothing else. The chart writes it into its
  datamodel, so whatever this step answers lands in engine state; the
  street address it looked at never does.

  The work is a read, so a job that runs twice answers twice the same
  way. The delay and failure hook is
  `StatifierExamples.FormPost.Steps.hooked/2`'s, under this module's
  name.
  """

  use StatifierOban.Invoke.Handler

  alias Statifier.Effect.Invoke
  alias StatifierExamples.FormPost.CardApplication
  alias StatifierExamples.FormPost.CardApplications.Reader
  alias StatifierExamples.FormPost.Steps

  @invoke_type "myapp:check_service_area"

  # Riverbend's streets, all of them made up.
  @riverbend_streets [
    "millrace lane",
    "ferry street",
    "willow bend road",
    "orchard row",
    "lantern court"
  ]

  @doc "The invoke type this step serves."
  @spec invoke_type() :: String.t()
  def invoke_type, do: @invoke_type

  @impl StatifierOban.Invoke.Handler
  @spec config() :: StatifierOban.Config.t()
  def config, do: Steps.config()

  @doc """
  Checks the application the params name against the service area.

  Answers `{:ok, "inside"}` or `{:ok, "outside"}`. An id that names no
  application in the library system answers
  `{:error, {:application_not_found, id}}`, and params that are not just
  an application id are refused; both retry, as every failure does.
  """
  @impl StatifierOban.Invoke.Handler
  @spec run(Invoke.t()) :: {:ok, String.t()} | {:error, term()}
  def run(%Invoke{params: params}) do
    Steps.hooked(__MODULE__, fn ->
      with {:ok, id} <- Steps.application_id(params),
           {:ok, application} <- read(id) do
        {:ok, area(application)}
      end
    end)
  end

  @spec read(integer()) :: {:ok, CardApplication.t()} | {:error, term()}
  defp read(id) do
    case Reader.fetch(Steps.library_system(), id) do
      {:ok, application} -> {:ok, application}
      {:error, :not_found} -> {:error, {:application_not_found, id}}
    end
  end

  # The street is what follows the house number; a street name inside a
  # longer one ("Ferry Street Extension") is not the street.
  @spec area(CardApplication.t()) :: String.t()
  defp area(%CardApplication{street_address: street_address}) do
    street = (street_address || "") |> String.downcase() |> String.trim()

    if Enum.any?(@riverbend_streets, &String.ends_with?(street, " " <> &1)),
      do: "inside",
      else: "outside"
  end
end
