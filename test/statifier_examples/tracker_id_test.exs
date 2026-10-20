defmodule StatifierExamples.TrackerIdTest do
  @moduledoc """
  No file under `lib/` gains a tracker id.

  A tracker id names an issue in one of the family's trackers: a repository
  prefix, a dash, and three or four base36 characters (`se-` then `06z`,
  say). In a moduledoc or a comment it points a reader at an issue instead
  of saying what the code does and why, and the issue text is not shipped
  with the code. Write the substance instead.

  ## Mechanism: a committed baseline

  `lib/` already carries such ids. Each one is counted in the committed
  baseline, `test/fixtures/tracker_id_baseline.txt`: per file, the id and
  how many times the file carries it. A count above the baseline fails,
  naming the file and the id; a count below it fails too, naming the
  baseline line to lower or delete, so an id that leaves a file cannot come
  back unseen. An existing occurrence that moves within its file changes no
  count. Like `StatifierExamples.PrivateIdTest`, it needs no git history and
  runs the same locally and in CI.

  ## What it does not catch

    * An id of a prefix missing from `@prefixes`: a tracker added to the
      family later is enforced only once its prefix is listed there.
    * An id that spells one of `@css_words`: those are the CSS class names
      in `lib/` that share the shape (`sr-only`), excluded by name.
    * An author who adds a baseline line beside a new id. The baseline's
      own header says a new id is refused, not added there, and a reviewer
      reads the diff.
  """
  use ExUnit.Case, async: true

  # Every tracker prefix in the family, one per repository.
  @prefixes ~w(ece enc eq ots pts px rd rs sb sd se sob sp sr st sui)

  # CSS class names in lib/ with a tracker id's shape. A class name is an
  # English word where an id has minted characters, so it is excluded by
  # name; everything else of the shape is an id.
  @css_words ~w(only)

  @tracker_id Regex.compile!(
                "\\b(?:" <>
                  Enum.join(@prefixes, "|") <>
                  ")-(?!(?:" <> Enum.join(@css_words, "|") <> ")\\b)[a-z0-9]{3,4}\\b"
              )

  @baseline "test/fixtures/tracker_id_baseline.txt"

  defp repo_path(relative), do: __DIR__ |> Path.join("../../#{relative}") |> Path.expand()

  # Every file under lib/, globbed at run time rather than listed, so a file
  # added later is enforced the moment it exists.
  defp lib_files do
    root = repo_path("")

    root
    |> Path.join("lib/**/*")
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
    |> Enum.map(&Path.relative_to(&1, root))
    |> Enum.sort()
  end

  defp tracker_ids(text), do: @tracker_id |> Regex.scan(text) |> Enum.map(&hd/1)

  defp tracker_id_counts(files) do
    for file <- files,
        {id, count} <-
          file |> repo_path() |> File.read!() |> tracker_ids() |> Enum.frequencies(),
        into: %{},
        do: {{file, id}, count}
  end

  defp read_baseline do
    @baseline
    |> repo_path()
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.reject(&String.starts_with?(&1, "#"))
    |> Map.new(fn line ->
      [file, id, count] = String.split(line, "\t")
      {{file, id}, String.to_integer(count)}
    end)
  end

  # Every invented id below is assembled from two halves at run time, so
  # this file's own source carries none of them.
  defp invented(prefix, rest), do: prefix <> rest

  # sabotage: drop "only" from @css_words -> red on the `sr-only` negative;
  # shorten the id shape to three characters -> red on a four-character
  # positive (both run 2026-09-30).
  test "the tracker-id pattern matches each prefix's id shape and no class name" do
    positives =
      for prefix <- @prefixes, rest <- ["zz9", "zz9q"] do
        id = invented(prefix <> "-", rest)
        {"filed as #{id} last week", id}
      end ++
        [
          {"(#{invented("se-", "zz9")}.2)", invented("se-", "zz9")},
          {"Bead `#{invented("sb-", "zz9q")}` builds it", invented("sb-", "zz9q")},
          {"# is a second one (#{invented("sp-", "zz9")}).", invented("sp-", "zz9")}
        ]

    for {text, id} <- positives, do: assert(tracker_ids(text) == [id], text)

    negatives = [
      ~s(<span class="sr-only">Actions</span>),
      ~s(<div class="sb-editor myapp-plan">),
      "`--sb-block-accent` and `--sb-block-accent-tint`",
      ~s(@accent_token "--sb-accent-myapp"),
      "the first-run path",
      "a post-1998 engine",
      "released as v0.32.0",
      "ADR-0005 part (iii)"
    ]

    for text <- negatives, do: assert(tracker_ids(text) == [], text)
  end

  # The comparison the baseline test makes, held apart from the file scan so
  # a small in-memory baseline and file set can drive both arms. Both maps
  # are keyed `{file, id}` and hold how many times the file carries the id.
  # Returns `{added, gone}`: the report lines for a count above the
  # baseline, and the baseline lines whose count the files fell below.
  defp compare_to_baseline(current, baseline) do
    added =
      for {{file, id} = key, count} <- current,
          count > Map.get(baseline, key, 0),
          do: "#{file}: #{id} (#{count} now, #{Map.get(baseline, key, 0)} before)"

    gone =
      for {{file, id} = key, before} <- baseline,
          Map.get(current, key, 0) < before,
          do: "#{file}\t#{id}\t#{before}"

    {Enum.sort(added), Enum.sort(gone)}
  end

  # sabotage: plant an invented tracker id in a lib/ file's moduledoc (for
  # example charts/fixture.ex) -> red on the first assertion, naming the
  # file and the id (run 2026-10-19). The baseline holds no line today, so
  # the second assertion cannot be driven from real data; the synthetic
  # test below drives both arms; make lib_files/0 return [] -> red on the
  # non-empty assertion (run 2026-10-19).
  test "no lib/ file gains a tracker id" do
    files = lib_files()
    # With an empty baseline and no ids, both lists below are empty either
    # way; a scan that found no files must not read as a pass.
    assert files != [], "no files found under lib/"

    {added, gone} = compare_to_baseline(tracker_id_counts(files), read_baseline())

    assert added == [],
           "new tracker ids in lib/ - write the substance instead:\n" <>
             Enum.join(added, "\n")

    assert gone == [],
           "ids removed since #{@baseline} was written - lower or delete " <>
             "these lines there so the id cannot come back unseen:\n" <>
             Enum.join(gone, "\n")
  end

  # sabotage: in compare_to_baseline/2, make `count > ...` a `count < ...`
  # (or drop the `added` comprehension's filter to never match) -> red on
  # the new-id and extra-copy assertions; make `Map.get(current, key, 0) <
  # before` never true -> red on the vanished-id and lowered-count
  # assertions (each run 2026-10-19).
  test "the baseline comparison reports a new id and a vanished id" do
    kept = invented("se-", "zz9")
    fresh = invented("sb-", "zz9q")
    leaving = invented("sp-", "zz8")
    shrinking = invented("sr-", "zz7")

    baseline = %{
      {"lib/a.ex", kept} => 1,
      {"lib/b.ex", leaving} => 1,
      {"lib/c.ex", shrinking} => 2
    }

    # No change: both arms stay quiet.
    assert compare_to_baseline(baseline, baseline) == {[], []}

    # A new id in a file, and an extra copy of an id the baseline knows.
    current = Map.merge(baseline, %{{"lib/d.ex", fresh} => 1, {"lib/a.ex", kept} => 2})

    assert compare_to_baseline(current, baseline) ==
             {["lib/a.ex: #{kept} (2 now, 1 before)", "lib/d.ex: #{fresh} (1 now, 0 before)"], []}

    # An id that left its file, and a count that fell below the baseline.
    current = baseline |> Map.delete({"lib/b.ex", leaving}) |> Map.put({"lib/c.ex", shrinking}, 1)

    assert compare_to_baseline(current, baseline) ==
             {[], ["lib/b.ex\t#{leaving}\t1", "lib/c.ex\t#{shrinking}\t2"]}

    # Both at once: the arms report independently.
    current = %{{"lib/a.ex", kept} => 1, {"lib/z.ex", fresh} => 1}

    assert compare_to_baseline(current, baseline) ==
             {["lib/z.ex: #{fresh} (1 now, 0 before)"],
              ["lib/b.ex\t#{leaving}\t1", "lib/c.ex\t#{shrinking}\t2"]}
  end
end
