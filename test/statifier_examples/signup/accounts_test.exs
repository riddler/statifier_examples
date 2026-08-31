defmodule StatifierExamples.Signup.AccountsTest do
  use ExUnit.Case, async: false

  import Ecto.Query, only: [from: 2]

  alias Ecto.Adapters.SQL.Sandbox
  alias StatifierExamples.Repo
  alias StatifierExamples.Signup.Accounts
  alias StatifierExamples.Signup.User

  setup do
    :ok = Sandbox.checkout(Repo)

    %{run: "run-#{System.unique_integer([:positive])}"}
  end

  defp count(email), do: Repo.one!(from(u in User, where: u.email == ^email, select: count()))

  # Sabotage: made `email_for/1` ignore its argument and answer a constant;
  # this went red on the second run id, then reverted.
  test "the address is a function of the run, so two runs are two accounts", %{run: run} do
    other = run <> "-other"

    assert Accounts.email_for(run) != Accounts.email_for(other)
    assert Accounts.email_for(run) == "signup-#{run}@example.com"
  end

  # Sabotage: dropped `on_conflict: :nothing` from the insert; this went red
  # with an `Exqlite.Error` on the UNIQUE constraint, then reverted.
  test "provisioning twice for one run writes one row", %{run: run} do
    email = Accounts.email_for(run)

    assert {:created, %User{email: ^email, id: id}} = Accounts.provision(run)
    assert {:existing, %User{email: ^email, id: ^id}} = Accounts.provision(run)

    assert count(email) == 1
  end

  # The tag is the part a reader sees in the run feed, and it is derived
  # from the write rather than guessed: a first delivery says `created` and
  # a replay says `existing`.
  #
  # Sabotage: made `tag/1` answer `:created` for both counts; this went red
  # on the second assertion, then reverted.
  test "the answer says which of the two happened", %{run: run} do
    assert {:created, _first} = Accounts.provision(run)
    assert {:existing, _second} = Accounts.provision(run)
  end
end
