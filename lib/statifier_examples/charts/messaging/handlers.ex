defmodule StatifierExamples.Charts.Messaging.Handlers do
  @moduledoc """
  The handler behind `myapp:notify`.

  Deployment state, supplied per session (statifier-ex ADR-0051), and the
  counterpart to `StatifierExamples.Charts.Messaging.Notify` on the other
  side of the two-registry seam. Like every handler in this app it logs one
  line and completes; the messages are fictional and nothing is sent.
  """

  require Logger

  @invoke_types ["myapp:notify"]

  @doc "Every invoke type this module answers."
  @spec invoke_types() :: [String.t()]
  def invoke_types, do: @invoke_types

  @doc """
  Answers a notify call, or refuses a name this module does not register.
  """
  @spec handle(String.t(), map()) :: {:ok, map()} | {:error, {:unknown_invoke_type, String.t()}}
  def handle("myapp:notify", params) do
    Logger.info("myapp:notify completed with #{map_size(params)} params")

    {:ok, %{}}
  end

  def handle(invoke_type, _params), do: {:error, {:unknown_invoke_type, invoke_type}}
end
