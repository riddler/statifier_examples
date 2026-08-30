defmodule StatifierExamples.RepoTest do
  @moduledoc """
  What the migrations actually built. These go through raw SQL rather than
  an Ecto schema on purpose: there is no `User` schema yet - the signup
  example writes its first row in a later bead - and a test that invented
  one would be testing the schema, not the table.
  """

  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL
  alias Ecto.Adapters.SQL.Sandbox
  alias StatifierExamples.Repo

  setup do
    :ok = Sandbox.checkout(Repo)
  end

  # Sabotage: drop the `email` column from the CreateUsers migration ->
  # red, the INSERT below fails with "table users has no column named
  # email". Verified red, reverted.
  test "the users table stores an address and stamps the row" do
    SQL.query!(
      Repo,
      "INSERT INTO users (email, inserted_at, updated_at) VALUES (?, ?, ?)",
      ["ada@example.com", DateTime.utc_now(), DateTime.utc_now()]
    )

    assert %{rows: [[email, inserted_at]]} =
             SQL.query!(Repo, "SELECT email, inserted_at FROM users", [])

    assert email == "ada@example.com"
    refute is_nil(inserted_at)
  end

  # Sabotage: drop `create(unique_index(:users, [:email]))` from the
  # CreateUsers migration -> red, the second insert succeeds and no
  # exception is raised. Verified red, reverted.
  test "the users table refuses a duplicate address" do
    insert = fn ->
      SQL.query!(
        Repo,
        "INSERT INTO users (email, inserted_at, updated_at) VALUES (?, ?, ?)",
        ["grace@example.com", DateTime.utc_now(), DateTime.utc_now()]
      )
    end

    insert.()

    assert_raise Exqlite.Error, ~r/UNIQUE constraint failed: users.email/, insert
  end

  # Sabotage: change the AddStatifierPersistence migration to
  # `up(for: ..., version: 1)` -> red, `statifier_runs` gains no `metadata`
  # column and the SELECT below fails with "no such column: metadata".
  # Verified red, reverted.
  test "the package tables carry every column its schemas select, V02 included" do
    for table <- ~w(statifier_charts statifier_positions statifier_runs) do
      assert %{rows: [[0]]} = SQL.query!(Repo, "SELECT count(*) FROM #{table}", [])
    end

    assert %{rows: []} = SQL.query!(Repo, "SELECT metadata FROM statifier_runs", [])
  end
end
