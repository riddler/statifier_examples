defmodule StatifierExamples.PrivateIdTest do
  @moduledoc """
  No file under `lib/` or `test/` gains a private ruling or question id.

  A private ruling or question id is a number on a list of decisions or
  open questions kept outside this repository, so a public reader cannot
  follow it. The ids already in `lib/` and `test/` stay where they are
  (each file that carries one says so in a dated note); a new one is
  refused, and the substance is written instead.

  ## Mechanism: a committed baseline, not a diff

  CI's `actions/checkout@v4` step sets no `fetch-depth`, so CI holds one
  commit and has no merge base to diff against. The test therefore
  compares against a committed baseline, `test/fixtures/private_id_baseline.txt`:
  per file, a digest of each id and how many times the file carries it.
  A count above the baseline fails, naming the file and the id; a count
  below it fails too, naming the baseline line to lower, so an id that
  leaves a file cannot come back unseen. That is "added lines only" in
  effect: an existing occurrence that moves within its file changes no
  count, and only a new occurrence raises one. It needs no git and runs
  the same locally and in CI.

  The baseline stores the first sixteen hex characters of each id's
  SHA-256, never the id itself: a committed list of the ids would be a
  new copy of every one of them in a public file.

  ## What it does not catch

    * A bare `R` or `Q` number with no ruling or question word beside it
      (see `@private_id`). Some of the existing ids are of that shape, and
      so are ordinary things this repository writes - an ADR's numbered
      sections, a quarter.
    * A bare decision number: `D` and digits with no dash and no second
      number, whatever word is beside it.
    * An author who adds a baseline line beside a new id. Nothing
      mechanical stops that; the baseline's own header says a new id is
      refused, not added there, and a reviewer reads the diff.
  """
  use ExUnit.Case, async: true

  # The shapes, each a separate alternative below:
  #
  # - a question id: `RQ-` and dash-separated alphanumeric parts (a
  #   campaign, then a number that a letter may follow);
  # - a ruling id qualified by a sub-number or a letter: `R`, digits, then
  #   `-`/`.` and digits, or one lower-case letter;
  # - a ruling id that is a bare letter: `R-` and one lower-case letter;
  # - a campaign decision id: `D`, the campaign's digits, `-`, digits;
  # - a bare `R`/`Q` number, only where a word names it as one ("ruling",
  #   "epic", "question" or "Riddler" before it, or "ruling" or "operator
  #   ruling" after it).
  @private_id ~r/
    \bRQ-[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*
    | \bR\d+(?:[-.]\d+|[a-z])\b
    | \bR-[a-z]\b
    | \bD\d+-\d+\b
    | \b(?:[Rr]ulings?|[Ee]pic|[Qq]uestions?|Riddler)\s+[`*]*\K[RQ]\d+(?:[-.]\d+|[a-z])?\b
    | \b[RQ]\d+(?:[-.]\d+|[a-z])?(?=[`*]*,?\s+(?:operator\s+)?ruling\b)
  /x

  @private_id_baseline "test/fixtures/private_id_baseline.txt"

  defp repo_path(relative), do: __DIR__ |> Path.join("../../#{relative}") |> Path.expand()

  defp scanned_files do
    root = repo_path("")

    (Path.wildcard(Path.join(root, "lib/**/*")) ++ Path.wildcard(Path.join(root, "test/**/*")))
    |> Enum.filter(&File.regular?/1)
    |> Enum.map(&Path.relative_to(&1, root))
    |> Enum.sort()
  end

  defp private_ids(text), do: @private_id |> Regex.scan(text) |> Enum.map(&hd/1)

  defp digest(id),
    do: :sha256 |> :crypto.hash(id) |> Base.encode16(case: :lower) |> binary_part(0, 16)

  defp private_id_counts(files) do
    for file <- files,
        {id, count} <-
          file |> repo_path() |> File.read!() |> private_ids() |> Enum.frequencies(),
        into: %{},
        do: {{file, digest(id)}, {id, count}}
  end

  defp read_baseline do
    @private_id_baseline
    |> repo_path()
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.reject(&String.starts_with?(&1, "#"))
    |> Map.new(fn line ->
      [file, digest, count] = String.split(line, "\t")
      {{file, digest}, String.to_integer(count)}
    end)
  end

  # Every invented id below is assembled from two halves at run time, so
  # this file's own source carries none of them and the scan of `test/`
  # below does not count them.
  defp invented(prefix, rest), do: prefix <> rest

  # sabotage: list the "Riddler" positive among the negatives, and
  # separately drop the word-named alternative from @private_id -> red
  # (both run 2026-09-19).
  test "the private-id pattern matches each id shape and no ordinary text" do
    positives = [
      {"see #{invented("RQ-", "XX999-99")} for why", invented("RQ-", "XX999-99")},
      {"see #{invented("RQ-", "999-9b")} for why", invented("RQ-", "999-9b")},
      {"under ruling #{invented("R", "99-9")}, the", invented("R", "99-9")},
      {"under ruling #{invented("R", "99.9")}, the", invented("R", "99.9")},
      {"as #{invented("R", "99z")} has it", invented("R", "99z")},
      {"campaign-999 ruling #{invented("R-", "z")} said", invented("R-", "z")},
      {"campaign-999 ruling `#{invented("D", "99-9")}` said", invented("D", "99-9")},
      {"under operator ruling #{invented("R", "98")}, the", invented("R", "98")},
      {"behind epic `#{invented("R", "97")}`", invented("R", "97")},
      {"open question #{invented("Q", "99")} asks", invented("Q", "99")},
      {"the subset is Riddler #{invented("R", "94")}'s to define", invented("R", "94")},
      {"the #{invented("R", "96")} ruling of", invented("R", "96")},
      {"(#{invented("R", "95")}, operator ruling 2026-01-01)", invented("R", "95")}
    ]

    for {text, id} <- positives, do: assert(private_ids(text) == [id], text)

    negatives = [
      "Rule 3 of the walk",
      "released as v0.32.0",
      "### R1. What `src` is",
      "sb ADR-0005 part (iii), clauses `15E` to `20E`",
      "the Riddler element document",
      "Document.rename(document, \"Q3 authorization\")",
      "RFC 7231 section 6",
      "a question the compiler asks",
      "the ruling of 2026-08-29"
    ]

    for text <- negatives, do: assert(private_ids(text) == [], text)
  end

  # sabotage: plant an invented question-shaped id in signup/path.ex's
  # moduledoc, and separately in this file's source -> red, naming the file
  # and the id; add a second copy of an id journey.ex already carries ->
  # red ("2 now, 1 before"); delete an id from guarded_step.ex -> red on
  # the second assertion (all four run 2026-09-19).
  test "no lib/ or test/ file gains a private ruling or question id" do
    baseline = read_baseline()
    current = private_id_counts(scanned_files())

    added =
      for {{file, _digest} = key, {id, count}} <- current,
          count > Map.get(baseline, key, 0),
          do: "#{file}: #{id} (#{count} now, #{Map.get(baseline, key, 0)} before)"

    gone =
      for {{file, digest} = key, before} <- baseline,
          Map.get(current, key, {nil, 0}) |> elem(1) < before,
          do: "#{file}\t#{digest}\t#{before}"

    assert added == [],
           "new private ruling or question ids - write the substance instead:\n" <>
             Enum.join(Enum.sort(added), "\n")

    assert gone == [],
           "ids removed since #{@private_id_baseline} was written - lower or " <>
             "delete these lines there so the id cannot come back unseen:\n" <>
             Enum.join(Enum.sort(gone), "\n")
  end
end
