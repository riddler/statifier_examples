defmodule StatifierExamples.DependencyPinsTest do
  @moduledoc """
  Guards the `statifier_persistence` requirement and its lock entry.

  This file guarded the interim git pin while no release carried the
  options this app configures; 0.2.0 does (the driver, `:blob_type`, the
  run `metadata` column), so the guard now holds the Hex floor. The
  half-move hazard is unchanged - a `mix.exs` edit without the matching
  `mix.lock` entry resolves to whatever was already fetched - so the two
  files are still checked against each other rather than each against a
  hope.
  """

  use ExUnit.Case, async: true

  # Sabotage: pointed the requirement expectation at the real-but-wrong
  # previous-era spelling `"~> 0.1.3"` and left `mix.exs` alone; the
  # membership assertion went red reporting `"~> 0.2"` against the mutated
  # expectation. Reverted from a backup copy. The lock assertion is what
  # ties the requirement to a resolved 0.2-line Hex release rather than a
  # leftover git checkout.
  test "statifier_persistence is the Hex requirement, in mix.exs and mix.lock alike" do
    deps = Mix.Project.config()[:deps]

    assert {:statifier_persistence, "~> 0.2"} in deps

    lock_line =
      "mix.lock"
      |> File.read!()
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, ~s(  "statifier_persistence": )))

    assert lock_line, "statifier_persistence has no mix.lock entry"
    assert lock_line =~ ~s({:hex, :statifier_persistence, "0.2.)
  end
end
