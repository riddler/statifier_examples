defmodule StatifierExamples.CardAuth.Handlers do
  @moduledoc """
  The other half of the two-registry seam: the handlers that answer the
  invoke types `StatifierExamples.CardAuth`'s block types name.

  A block type is authoring state, supplied per editing or compiling
  operation as part of a palette. A handler is deployment state, supplied
  per session (statifier-ex ADR-0051). Nothing here is reachable from a
  block type and nothing there is reachable from here, which is the whole
  point of there being two registries.

  Every handler in this app logs one line and completes. That is not a
  placeholder for something richer: a reference embedder exists to show
  the *shape* of the seam, and a handler that also moved money would make
  the shape harder to read, not easier. The values in the log line are
  fictional in exactly the way this repo's fixtures are.
  """

  require Logger

  @invoke_types [
    "myapp:authorize",
    "myapp:balance_check",
    "myapp:capture",
    "myapp:intake",
    "myapp:manual_flag",
    "myapp:park",
    "myapp:receipt",
    "myapp:resolve_review",
    "myapp:risk_rating",
    "myapp:three_ds"
  ]

  @doc """
  Every invoke type this module answers, sorted.

  The list a host hands the compiler as `:known_invoke_types`, which is
  what turns "this document names a handler nobody registered" from a
  runtime surprise into a compile-time warning.
  """
  @spec invoke_types() :: [String.t()]
  def invoke_types, do: @invoke_types

  @doc """
  Answers one call, or refuses a name this module does not register.

  `{:error, {:unknown_invoke_type, type}}` rather than a raise, because an
  unregistered invoke type is an ordinary answer a caller routes on - this
  family's rule is that errors are events, and a leaf never rescues to a
  default.
  """
  @spec handle(String.t(), map()) :: {:ok, map()} | {:error, {:unknown_invoke_type, String.t()}}
  def handle("myapp:authorize", params), do: completed("myapp:authorize", params)
  def handle("myapp:balance_check", params), do: completed("myapp:balance_check", params)
  def handle("myapp:capture", params), do: completed("myapp:capture", params)
  def handle("myapp:intake", params), do: completed("myapp:intake", params)
  def handle("myapp:manual_flag", params), do: completed("myapp:manual_flag", params)
  def handle("myapp:park", params), do: completed("myapp:park", params)
  def handle("myapp:receipt", params), do: completed("myapp:receipt", params)
  def handle("myapp:resolve_review", params), do: completed("myapp:resolve_review", params)
  def handle("myapp:risk_rating", params), do: completed("myapp:risk_rating", params)
  def handle("myapp:three_ds", params), do: completed("myapp:three_ds", params)
  def handle(invoke_type, _params), do: {:error, {:unknown_invoke_type, invoke_type}}

  @spec completed(String.t(), map()) :: {:ok, map()}
  defp completed(invoke_type, params) do
    Logger.info("#{invoke_type} completed with #{map_size(params)} params")

    {:ok, %{}}
  end
end
