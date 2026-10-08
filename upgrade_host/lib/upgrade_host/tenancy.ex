defmodule UpgradeHost.Tenancy do
  @moduledoc """
  The host's tenancy context: the branch the current work runs for, held
  in the process. A multi-tenant host runs every step of every execution
  under it, and its own code reads it with `current!/0`, which raises
  when no branch is set rather than writing a row that belongs to none.

  `run/2` is the one way to set it: the branch is set for the length of
  the function and the earlier value put back after it, whatever the
  function does.
  """

  @key {__MODULE__, :branch_id}

  @doc "Runs `fun` with `branch_id` as the current branch, and answers what it answered."
  @spec run(String.t(), (-> result)) :: result when result: term()
  def run(branch_id, fun) when is_binary(branch_id) and is_function(fun, 0) do
    previous = Process.put(@key, branch_id)

    try do
      fun.()
    after
      if previous, do: Process.put(@key, previous), else: Process.delete(@key)
    end
  end

  @doc "The current branch, or `nil` outside `run/2`."
  @spec current() :: String.t() | nil
  def current, do: Process.get(@key)

  @doc "The current branch; raises outside `run/2`."
  @spec current!() :: String.t()
  def current! do
    case current() do
      nil -> raise "no branch is set: this work must run inside UpgradeHost.Tenancy.run/2"
      branch_id -> branch_id
    end
  end
end
