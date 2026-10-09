defmodule StatifierExamples.FormPost.SortApplication do
  @moduledoc """
  The card application's sort, the `myapp:sort_application` step: handed
  an application's id, it answers `"card"`, `"newsletter"`, `"both"` or
  `"neither"`.

  The word says which of the library's two services the visitor asked
  for: a borrowing card, the events newsletter, both, or neither. The
  chart's two lanes each read it, the card lane on `"card"` or `"both"`
  and the newsletter lane on `"newsletter"` or `"both"`, so the two
  checkboxes the visitor ticked stay in the host's table and only the word
  reaches the chart's datamodel.

  The form refuses an application that asks for neither, so `"neither"`
  is an answer for a row stored some other way: the step reads what is
  stored and does not assume what the form allowed.

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

  @invoke_type "myapp:sort_application"

  @doc "The invoke type this step serves."
  @spec invoke_type() :: String.t()
  def invoke_type, do: @invoke_type

  @impl StatifierOban.Invoke.Handler
  @spec config() :: StatifierOban.Config.t()
  def config, do: Steps.config()

  @doc """
  Sorts the application the params name.

  Answers `{:ok, "card"}`, `{:ok, "newsletter"}`, `{:ok, "both"}` or
  `{:ok, "neither"}`. An id that names no application in the library
  system answers `{:error, {:application_not_found, id}}`, and params
  that are not just an application id are refused; both retry, as every
  failure does.
  """
  @impl StatifierOban.Invoke.Handler
  @spec run(Invoke.t()) :: {:ok, String.t()} | {:error, term()}
  def run(%Invoke{params: params}) do
    Steps.hooked(__MODULE__, fn ->
      with {:ok, id} <- Steps.application_id(params),
           {:ok, application} <- read(id) do
        {:ok, sort(application)}
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

  @spec sort(CardApplication.t()) :: String.t()
  defp sort(%CardApplication{wants_card: true, wants_newsletter: true}), do: "both"
  defp sort(%CardApplication{wants_card: true}), do: "card"
  defp sort(%CardApplication{wants_newsletter: true}), do: "newsletter"
  defp sort(%CardApplication{}), do: "neither"
end
