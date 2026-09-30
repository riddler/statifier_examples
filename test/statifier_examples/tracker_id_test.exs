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

  # sabotage: plant an invented tracker id in charts/fixture.ex's moduledoc
  # -> red, naming the file and the id; add a second copy of an id
  # documents.ex already carries -> red ("2 now, 1 before"); delete the id
  # from charts/fan_out.ex's moduledoc -> red on the second assertion
  # (all three run 2026-09-30).
  test "no lib/ file gains a tracker id" do
    baseline = read_baseline()
    current = tracker_id_counts(lib_files())

    added =
      for {{file, id} = key, count} <- current,
          count > Map.get(baseline, key, 0),
          do: "#{file}: #{id} (#{count} now, #{Map.get(baseline, key, 0)} before)"

    gone =
      for {{file, id} = key, before} <- baseline,
          Map.get(current, key, 0) < before,
          do: "#{file}\t#{id}\t#{before}"

    assert added == [],
           "new tracker ids in lib/ - write the substance instead:\n" <>
             Enum.join(Enum.sort(added), "\n")

    assert gone == [],
           "ids removed since #{@baseline} was written - lower or delete " <>
             "these lines there so the id cannot come back unseen:\n" <>
             Enum.join(Enum.sort(gone), "\n")
  end
end
