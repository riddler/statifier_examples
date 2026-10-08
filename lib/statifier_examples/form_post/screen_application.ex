defmodule StatifierExamples.FormPost.ScreenApplication do
  @moduledoc """
  The card application's screen, the `myapp:screen_application` step:
  handed an application's id, it answers `"ok"` or `"screened_out"`.

  The rule is a teaching rule, not a library's policy: an application
  whose street address is a post office box is screened out, because a
  borrowing card is issued to a home address. A host's real screen sits
  where `screen/1` does, reads what it needs through the same reader, and
  answers a word the chart's conditions can read.

  The answer is the word and nothing else. The chart writes it into its
  datamodel, so whatever this step answers lands in engine state; the
  street address it looked at never does.

  The work is a read, so a job that runs twice answers twice the same
  way: the at-least-once contract costs nothing here. The delay and
  failure hook is `StatifierExamples.FormPost.Steps.hooked/2`'s, under
  this module's name.
  """

  use StatifierOban.Invoke.Handler

  alias Statifier.Effect.Invoke
  alias StatifierExamples.FormPost.CardApplication
  alias StatifierExamples.FormPost.CardApplications.Reader
  alias StatifierExamples.FormPost.Steps

  @invoke_type "myapp:screen_application"

  # A post office box, written the ways a visitor types one.
  @post_office_box ~r/\bp\.?\s*o\.?\s+box\b/i

  @doc "The invoke type this step serves."
  @spec invoke_type() :: String.t()
  def invoke_type, do: @invoke_type

  @impl StatifierOban.Invoke.Handler
  @spec config() :: StatifierOban.Config.t()
  def config, do: Steps.config()

  @doc """
  Screens the application the params name.

  Answers `{:ok, "ok"}` or `{:ok, "screened_out"}`. An id that names no
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
        {:ok, screen(application)}
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

  @spec screen(CardApplication.t()) :: String.t()
  defp screen(%CardApplication{street_address: street_address}) do
    if Regex.match?(@post_office_box, street_address || ""), do: "screened_out", else: "ok"
  end
end
