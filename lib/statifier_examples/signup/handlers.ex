defmodule StatifierExamples.Signup.Handlers do
  @moduledoc """
  The host handlers the signup wizard's block types name.

  A block type names an invoke type; a handler runs one, and which handler a
  name resolves to is deployment state supplied per session (statifier-ex
  ADR-0051). This module is the deployment half for this app's signup
  domain, written in the one shape every handler module here uses:
  `invoke_types/0` answers every name it registers, and `handle/2` answers
  one call or refuses a name it does not.

  That shape is the one the runtime asks for. ADR-0051's per-session
  registration is a `%{invoke type => module}` map, so a handler is a
  *module* rather than a closure, and the set the compiler wants as
  `:known_invoke_types` is the same map's keys - which `invoke_types/0`
  answers directly, without a caller reaching into a map of functions to
  find out what this module can do.

  What the handlers do here is log a line and answer `{:ok, %{}}`. That is
  the whole point of an example: the chart is the interesting part, and a
  handler that pretended to create a workspace would only be fiction with
  more moving parts. Every value that reaches them is fictional too -
  `@example.com` addresses and made-up plan names.
  """

  require Logger

  @invoke_types [
    "myapp:provision",
    "myapp:signup"
  ]

  @doc """
  Every invoke type this module answers, sorted.

  Part of the list a host hands the compiler as `:known_invoke_types`,
  which is what turns "this document names a handler nobody registered"
  from a runtime surprise into a compile-time warning.
  """
  @spec invoke_types() :: [String.t()]
  def invoke_types, do: @invoke_types

  @doc """
  Answers one call, or refuses a name this module does not register.

  `{:error, {:unknown_invoke_type, type}}` rather than a raise, because an
  unregistered invoke type is an ordinary answer a caller routes on - this
  family's rule is that errors are events, and a leaf never rescues to a
  default.

  `myapp:signup` collects one step of the wizard, and `params` carries the
  `step` the block emitted as a literal `<param>`, so the handler learns
  which form to put up without reading the datamodel. `myapp:provision`
  creates the workspace the finished signup gets.
  """
  @spec handle(String.t(), map()) :: {:ok, map()} | {:error, {:unknown_invoke_type, String.t()}}
  def handle("myapp:signup", params) do
    Logger.info("myapp:signup collected step #{inspect(Map.get(params, "step"))}")

    {:ok, %{}}
  end

  def handle("myapp:provision", params) do
    Logger.info("myapp:provision created a workspace from #{inspect(Map.keys(params))}")

    {:ok, %{}}
  end

  def handle(invoke_type, _params), do: {:error, {:unknown_invoke_type, invoke_type}}
end
