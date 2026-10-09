defmodule StatifierExamples.FormPost.Scope do
  @moduledoc """
  The library system a card application's delivery runs for, held in the
  process while the router does that delivery's work: this app's stand-in
  for a host's tenancy context.

  A host that keeps one tenant's rows apart from another's usually sets a
  tenancy context before any read or write and clears it after. The
  router's `:around_delivery` is the seam for that: it is handed
  `(scope, door, work)` around every door the router drives itself, and
  `around_delivery/3` here is this app's value for it in
  `StatifierExamples.FormPost.Router.config/0`. It puts the scope, the
  library system the router was handed, into the process dictionary, runs
  the work exactly once, and puts back what was there before, on every way
  out.

  `fetch/0` is how code inside the delivery reads it.
  `StatifierExamples.FormPost.Stepper` refuses to create or step an
  execution when no library system is held, the way a host's own engine
  door refuses to run outside a tenant. The scope is a library system's
  name (`"riverbend"`), never a value the visitor typed.

  A process dictionary is the plainest such context. A host on Postgres
  might instead open a transaction on the router's repo here and set a
  transaction-local setting before calling the work, which
  `StatifierRouter.Config`'s documentation describes.
  """

  @key {__MODULE__, :library_system}

  @doc """
  Runs `work` with `scope` held as the library system, under the router's
  `door`, and answers what `work` answered.

  The value held before the call is restored afterwards, so a delivery
  nested inside another keeps the outer library system once it returns.
  """
  @spec around_delivery(String.t(), atom(), (-> answer)) :: answer when answer: term()
  def around_delivery(scope, _door, work) when is_binary(scope) and is_function(work, 0) do
    previous = Process.put(@key, scope)

    try do
      work.()
    after
      restore(previous)
    end
  end

  @doc """
  The library system held in this process, or `{:error, :no_library_system}`
  outside any delivery.
  """
  @spec fetch() :: {:ok, String.t()} | {:error, :no_library_system}
  def fetch do
    case Process.get(@key) do
      scope when is_binary(scope) -> {:ok, scope}
      nil -> {:error, :no_library_system}
    end
  end

  @spec restore(String.t() | nil) :: term()
  defp restore(nil), do: Process.delete(@key)
  defp restore(previous), do: Process.put(@key, previous)
end
