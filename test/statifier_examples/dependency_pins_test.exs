defmodule StatifierExamples.DependencyPinsTest do
  @moduledoc """
  Guards the interim git pin.

  `statifier_persistence` is taken from a git ref rather than Hex because
  no release carries the options this app configures. A pin like that is
  easy to leave behind and easy to half-move - a `mix.exs` edit without
  the matching `mix.lock` entry resolves to whatever was already fetched
  - so the ref is asserted here, in one place, and the two files are
  checked against each other rather than each against a hope.
  """

  use ExUnit.Case, async: true

  @statifier_persistence_ref "08c991cf5fbce37d7de81a05be60b64b92b9bb02"

  # Sabotage: point mix.exs's `ref:` at ca8a7d8921a321491843934386e3ffa4ddf85f65
  # (the ref this app carried before se-4dt.3, a real commit, so
  # `mix deps.get` still succeeds and ExUnit still runs), then
  # `mix deps.get` -> red, both assertions below report the previous ref.
  # Verified red, reverted.
  test "statifier_persistence is pinned to the recorded git ref, in mix.exs and mix.lock alike" do
    assert File.read!("mix.exs") =~ ~s(ref: "#{@statifier_persistence_ref}")

    lock_line =
      "mix.lock"
      |> File.read!()
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, ~s(  "statifier_persistence": )))

    assert lock_line, "statifier_persistence has no mix.lock entry"
    assert lock_line =~ @statifier_persistence_ref
  end
end
