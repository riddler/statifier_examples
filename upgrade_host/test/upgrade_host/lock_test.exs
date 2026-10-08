defmodule UpgradeHost.LockTest do
  @moduledoc """
  The host's family set, held exactly. A step forward moves a pin in
  mix.exs and one line set in mix.lock, together and on purpose; a lock
  that drifts on its own, or a pin that loosens, is red here.
  """

  use ExUnit.Case, async: true

  # Every package the host pins, at the version it runs. The opentelemetry
  # SDK is the suite's own, test-only, and is held here too so its line
  # cannot move unnoticed either.
  @pinned %{
    statifier: "2.12.1",
    statifier_blocks: "0.39.0",
    statifier_persistence: "0.19.0",
    statifier_oban: "0.15.0",
    statifier_router: "0.7.0",
    opentelemetry_statifier: "0.7.0",
    statifier_ui: "0.10.2",
    statifier_datamodel: "0.5.1",
    predicator: "9.4.3",
    uxid: "2.9.2",
    oban: "2.19.4",
    ecto_sql: "3.14.0",
    postgrex: "0.22.4",
    opentelemetry_api: "1.5.0",
    opentelemetry: "1.7.0"
  }

  @root Path.expand("../..", __DIR__)

  # sabotage: pinned statifier at "== 2.10.0" and ran mix deps.update
  # statifier, moving the lock with it -> red here, statifier at 2.10.0.
  test "mix.lock carries every pinned package from Hex at exactly its pinned version" do
    lock = read_lock()

    for {package, version} <- @pinned do
      assert {:hex, ^package, ^version, _hash, _managers, _deps, "hexpm", _outer} =
               Map.get(lock, package)
    end
  end

  # sabotage: loosened statifier's requirement in mix.exs to "~> 2.9.0"
  # -> red, naming statifier.
  test "mix.exs pins every family package exactly, from Hex, with no override" do
    deps = Mix.Project.config()[:deps]

    for {package, version} <- @pinned do
      assert dep = List.keyfind(deps, package, 0), "#{package} is not in mix.exs"
      {^package, requirement, opts} = normalize(dep)

      assert requirement == "== " <> version, "#{package} is pinned #{inspect(requirement)}"

      for forbidden <- [:path, :git, :github, :override, :in_umbrella] do
        refute Keyword.has_key?(opts, forbidden), "#{package} carries #{forbidden}:"
      end
    end
  end

  test "nothing in mix.exs is a path, git or override dependency" do
    for dep <- Mix.Project.config()[:deps] do
      {package, _requirement, opts} = normalize(dep)

      for forbidden <- [:path, :git, :github, :override, :in_umbrella] do
        refute Keyword.has_key?(opts, forbidden), "#{package} carries #{forbidden}:"
      end
    end
  end

  # The lock is an Elixir map literal; read it as Mix does, without the
  # parser warning about its quoted keys.
  defp read_lock do
    {lock, _binding} =
      @root
      |> Path.join("mix.lock")
      |> File.read!()
      |> Code.string_to_quoted!(emit_warnings: false)
      |> Code.eval_quoted()

    lock
  end

  defp normalize({package, requirement}) when is_binary(requirement),
    do: {package, requirement, []}

  defp normalize({package, requirement, opts}) when is_binary(requirement),
    do: {package, requirement, opts}

  defp normalize({package, opts}) when is_list(opts), do: {package, nil, opts}
end
