defmodule StatifierExamples.Signup.Handlers do
  @moduledoc """
  The host handlers the signup wizard's block types name.

  A block type names an invoke type; a handler runs one, and which handler a
  name resolves to is deployment state supplied per session (statifier-ex
  ADR-0051). This module is the deployment half for this app's signup
  domain: `handlers/0` is the map a session registers, and the two functions
  under it are what a real host would put its own work in.

  What they do here is log a line and answer `{:ok, %{}}`. That is the whole
  point of an example: the chart is the interesting part, and a handler that
  pretended to create a workspace would only be fiction with more moving
  parts. Every value that reaches them is fictional too - `@example.com`
  addresses and made-up plan names.
  """

  require Logger

  @typedoc "What a session registers: an invoke type, and the function that runs it."
  @type handler :: (map() -> {:ok, map()})

  @doc "The signup domain's handlers, keyed by the invoke type each one answers."
  @spec handlers() :: %{optional(String.t()) => handler()}
  def handlers,
    do: %{
      "myapp:signup" => &__MODULE__.signup/1,
      "myapp:provision" => &__MODULE__.provision/1
    }

  @doc """
  Handles `myapp:signup`: one step of the wizard.

  `params` carries the `step` the block emitted as a literal `<param>`.
  """
  @spec signup(map()) :: {:ok, map()}
  def signup(params) when is_map(params) do
    Logger.info("myapp:signup collected step #{inspect(Map.get(params, "step"))}")
    {:ok, %{}}
  end

  @doc "Handles `myapp:provision`: the workspace the finished signup gets."
  @spec provision(map()) :: {:ok, map()}
  def provision(params) when is_map(params) do
    Logger.info("myapp:provision created a workspace from #{inspect(Map.keys(params))}")
    {:ok, %{}}
  end
end
