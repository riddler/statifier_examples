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
  # `up(for: ..., version: 1)` -> red, `statifier_executions` gains no `metadata`
  # column and the SELECT below fails with "no such column: metadata".
  # Verified red, reverted.
  test "the package tables carry every column its schemas select, V02 included" do
    for table <- ~w(statifier_charts statifier_positions statifier_executions) do
      assert %{rows: [[0]]} = SQL.query!(Repo, "SELECT count(*) FROM #{table}", [])
    end

    assert %{rows: []} = SQL.query!(Repo, "SELECT metadata FROM statifier_executions", [])
  end

  # V09 (`statifier_persistence` 0.26.0): the six linkage columns and their
  # two indexes. This app leaves `linkage_columns:` off, so no schema here
  # selects them and nothing else in the suite would notice them missing.
  #
  # Sabotage: removed the AddStatifierPersistenceLinkageColumns migration
  # and dropped the test database -> red on the column assertion, none of
  # the six columns present. Reverted from a copy.
  test "the executions table carries V09's linkage columns and indexes" do
    %{rows: column_rows} = SQL.query!(Repo, "PRAGMA table_info(statifier_executions)", [])
    present = Enum.map(column_rows, &Enum.at(&1, 1))

    assert ~w(linkage_parent_execution_id linkage_invoke_id linkage_child_index
              linkage_content_hash linkage_child_count linkage_policy) -- present == []

    %{rows: rows} = SQL.query!(Repo, "PRAGMA index_list(statifier_executions)", [])
    indexed = Enum.flat_map(rows, &index_columns(Enum.at(&1, 1)))

    assert ["linkage_parent_execution_id", "linkage_invoke_id"] in indexed
    assert ["linkage_content_hash"] in indexed
  end

  defp index_columns(name) do
    %{rows: rows} = SQL.query!(Repo, "PRAGMA index_info(#{name})", [])
    [Enum.map(rows, &Enum.at(&1, 2))]
  end
end
