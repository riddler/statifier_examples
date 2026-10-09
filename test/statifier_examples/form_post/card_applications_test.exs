defmodule StatifierExamples.FormPost.CardApplicationsTest do
  @moduledoc """
  The host's own write for the Riverbend Public Library's card application
  form: one row per application, deduplicated on the client's key, and an
  intake job that carries the row's id and nothing else.
  """

  # Not async: writes to the repo.
  use ExUnit.Case, async: false
  # The engine and notifier are named because `Oban.Testing` builds its
  # own config, whose defaults are Postgres'; this app's Oban is SQLite's.
  use Oban.Testing,
    repo: StatifierExamples.Repo,
    engine: Oban.Engines.Lite,
    notifier: Oban.Notifiers.PG

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias StatifierExamples.FormPost.{CardApplication, CardApplications, IntakeJob}
  alias StatifierExamples.Repo

  setup do
    :ok = Sandbox.checkout(Repo)

    :ok
  end

  defp form(overrides \\ %{}) do
    Map.merge(
      %{
        "name" => "Wren Alder",
        "email" => "wren.alder@example.com",
        "phone" => "555-0142",
        "street_address" => "12 Millrace Lane",
        "wants_card" => "true",
        "wants_newsletter" => "false",
        "idempotency_key" => "form-7f3a"
      },
      overrides
    )
  end

  # Sabotage: made `receive_application/2` skip the `Oban.insert!/1` step
  # of its transaction; this went red on `assert_enqueued`. Reverted.
  test "a new application is stored as received and its intake job carries the id only" do
    assert {:ok, %CardApplication{id: id} = application, :created} =
             CardApplications.receive_application("riverbend", form())

    assert %CardApplication{
             scope: "riverbend",
             name: "Wren Alder",
             email: "wren.alder@example.com",
             phone: "555-0142",
             street_address: "12 Millrace Lane",
             wants_card: true,
             wants_newsletter: false,
             idempotency_key: "form-7f3a",
             status: "received",
             external_reference: nil
           } = Repo.get!(CardApplication, id)

    assert application.status == "received"

    assert_enqueued(worker: IntakeJob, args: %{"application_id" => id})

    assert [%Oban.Job{args: args, queue: "card_application_intake"}] =
             all_enqueued(worker: IntakeJob)

    assert args == %{"application_id" => id}
  end

  # Sabotage: dropped `on_conflict: :nothing` from the insert, so a
  # repeat answered the unique constraint's changeset error; this went red
  # on the second call's match. Reverted.
  test "a repeated key answers the first row and inserts and enqueues nothing new" do
    assert {:ok, %CardApplication{id: id}, :created} =
             CardApplications.receive_application("riverbend", form())

    assert {:ok, %CardApplication{id: ^id, status: "received"}, :repeat} =
             CardApplications.receive_application(
               "riverbend",
               form(%{"name" => "Someone Else", "email" => "someone.else@example.com"})
             )

    assert Repo.aggregate(CardApplication, :count) == 1
    assert %CardApplication{name: "Wren Alder"} = Repo.get!(CardApplication, id)
    assert [%Oban.Job{}] = all_enqueued(worker: IntakeJob)
  end

  # Sabotage: made the repeat's read select the whole row; this went red
  # on the four personal fields' nil match. Reverted.
  test "a repeat's answer carries none of the personal fields" do
    assert {:ok, %CardApplication{}, :created} =
             CardApplications.receive_application("riverbend", form())

    assert {:ok, repeat, :repeat} = CardApplications.receive_application("riverbend", form())

    assert %CardApplication{
             scope: "riverbend",
             name: nil,
             email: nil,
             phone: nil,
             street_address: nil,
             wants_card: true,
             wants_newsletter: false,
             idempotency_key: "form-7f3a"
           } = repeat
  end

  # Sabotage: made `receive_application/2` store every application under
  # one library system, whatever `scope` it was given; this went red on the
  # second library system's `:created`. Reverted.
  test "the same key in another library system is another application" do
    assert {:ok, %CardApplication{id: first}, :created} =
             CardApplications.receive_application("riverbend", form())

    assert {:ok, %CardApplication{id: second, scope: "eastbank"}, :created} =
             CardApplications.receive_application("eastbank", form())

    assert first != second
  end

  # Sabotage: dropped the "at least one interest" validation from
  # `CardApplication.changeset/2`; this went red on the no-interest
  # refusal. Reverted.
  test "a refused form stores nothing and enqueues nothing" do
    assert {:error, %Ecto.Changeset{} = changeset} =
             CardApplications.receive_application("riverbend", form(%{"name" => ""}))

    assert %{name: ["can't be blank"]} = errors(changeset)

    assert {:error, changeset} =
             CardApplications.receive_application(
               "riverbend",
               form(%{"email" => "not-an-address"})
             )

    assert %{email: ["must be an email address"]} = errors(changeset)

    assert {:error, changeset} =
             CardApplications.receive_application(
               "riverbend",
               form(%{"wants_card" => "false", "wants_newsletter" => "false"})
             )

    assert %{wants_card: ["choose a library card, the newsletter, or both"]} = errors(changeset)

    assert {:error, changeset} =
             CardApplications.receive_application(
               "riverbend",
               Map.delete(form(), "idempotency_key")
             )

    assert %{idempotency_key: ["can't be blank"]} = errors(changeset)

    assert Repo.aggregate(CardApplication, :count) == 0
    assert [] = all_enqueued(worker: IntakeJob)
  end

  # Sabotage: made `CardApplication.changeset/2` cast `scope`, `status`
  # and `external_reference` from the form; this went red on the stored row's
  # three host-owned columns. Reverted.
  test "the form cannot set the library system, the status or the outside reference" do
    assert {:ok, %CardApplication{id: id}, :created} =
             CardApplications.receive_application(
               "riverbend",
               form(%{"scope" => "eastbank", "status" => "sent", "external_reference" => "P-1"})
             )

    assert [{"riverbend", "received", nil}] =
             Repo.all(
               from(a in CardApplication,
                 where: a.id == ^id,
                 select: {a.scope, a.status, a.external_reference}
               )
             )
  end

  defp errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
  end
end
