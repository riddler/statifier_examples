defmodule StatifierExamples.FormPost.RetentionTest do
  @moduledoc """
  The card application recipe's retention, which is the host's: the purge
  of the stored applications' personal fields, the engine's own prune, and
  the router's reapers, all on this app's crontab.

  The suite runs Oban in `testing: :manual`, which starts no plugin, so no
  job runs here on its own. Each test hands the job's function a clock of
  its own and places rows either side of the configured age.
  """

  # Not async: writes to the repo.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias StatifierExamples.FormPost
  alias StatifierExamples.FormPost.{CardApplication, CardApplications, PruneJob, PurgeJob}
  alias StatifierExamples.Persistence
  alias StatifierExamples.Repo
  alias StatifierExamples.RoutedWorkflow.{AddressReaper, DedupeReaper}
  alias StatifierPersistence.Storage
  alias StatifierRouter.Schema.Address

  @now ~U[2026-03-02 12:00:00.000000Z]
  @day 86_400

  setup do
    :ok = Sandbox.checkout(Repo)
  end

  defp age(job, key),
    do: :statifier_examples |> Application.fetch_env!(job) |> Keyword.fetch!(key)

  defp days_before(days, now \\ @now), do: DateTime.add(now, -round(days * @day), :second)

  # Stores an application through the host's own write, then sets its
  # status and its stamp as an outcome recorded `days` before `@now`.
  defp application(key, status, days, scope \\ "riverbend") do
    form = %{
      "name" => "Juniper Vale",
      "email" => "juniper.vale@example.com",
      "phone" => "555-0178",
      "street_address" => "4 Larkspur Row",
      "wants_card" => "true",
      "idempotency_key" => key
    }

    {:ok, %CardApplication{id: id}, :created} = CardApplications.receive_application(scope, form)

    {1, _} =
      Repo.update_all(from(a in CardApplication, where: a.id == ^id),
        set: [status: status, updated_at: days_before(days)]
      )

    id
  end

  defp cleared?(id) do
    case Repo.get!(CardApplication, id) do
      %CardApplication{name: "", email: "", phone: nil, street_address: ""} -> true
      %CardApplication{name: "Juniper Vale", email: "juniper.vale@example.com"} -> false
    end
  end

  describe "the purge of the stored applications" do
    # Sabotage: made `purge_personal_fields/3` select `a.updated_at >
    # ^cutoff` instead of `<` -> red, the sent application past the age is
    # kept and the one inside it is cleared.
    test "a sent application is cleared past the sent age and kept inside it" do
      days = age(PurgeJob, :sent_after_days)
      old = application("sent-old", "sent", days + 1)
      recent = application("sent-recent", "sent", days - 1)

      assert {:ok, %{"riverbend" => %{"sent" => 1, "screened_out" => 0}}} = PurgeJob.purge(@now)

      assert cleared?(old)
      refute cleared?(recent)
    end

    # Sabotage: made `purge/1` read `:sent_after_days` for the screened-out
    # status too -> red, the screened-out application past its own age is
    # kept.
    test "a screened-out application is cleared past its own age and kept inside it" do
      days = age(PurgeJob, :screened_out_after_days)
      old = application("screened-old", "screened_out", days + 1)
      recent = application("screened-recent", "screened_out", days - 1)

      assert {:ok, %{"riverbend" => %{"screened_out" => 1}}} = PurgeJob.purge(@now)

      assert cleared?(old)
      refute cleared?(recent)
    end

    # Sabotage: dropped `a.status == ^status` from the purge's query -> red,
    # the received application is cleared by the sent sweep.
    test "an application still in flight is never cleared, however old" do
      oldest =
        Enum.max([age(PurgeJob, :sent_after_days), age(PurgeJob, :screened_out_after_days)])

      received = application("still-received", "received", oldest + 100)

      assert {:ok, %{"riverbend" => %{"sent" => 0, "screened_out" => 0}}} = PurgeJob.purge(@now)

      refute cleared?(received)
    end

    # Sabotage: dropped `a.scope == ^scope` from the purge's query -> red,
    # the other library system's application is cleared too.
    test "the purge clears only the library systems the app serves" do
      neighbour =
        application("neighbour", "sent", age(PurgeJob, :sent_after_days) + 1, "elmhurst")

      assert {:ok, counts} = PurgeJob.purge(@now)

      assert Map.keys(counts) == ["riverbend"]
      refute cleared?(neighbour)
    end

    # Sabotage: made `purge_personal_fields/3` delete the rows instead of
    # clearing their fields -> red, the repeat post stores a new
    # application under the same key.
    test "a cleared application keeps its id and key, so a repeat post still matches it" do
      id = application("repeat-me", "sent", age(PurgeJob, :sent_after_days) + 1)

      assert {:ok, _counts} = PurgeJob.purge(@now)

      repeat = %{
        "name" => "Juniper Vale",
        "email" => "juniper.vale@example.com",
        "street_address" => "4 Larkspur Row",
        "wants_card" => "true",
        "idempotency_key" => "repeat-me"
      }

      assert {:ok, %CardApplication{id: ^id}, :repeat} =
               CardApplications.receive_application("riverbend", repeat)

      assert [
               %CardApplication{
                 id: ^id,
                 scope: "riverbend",
                 idempotency_key: "repeat-me",
                 status: "sent",
                 wants_card: true
               }
             ] = Repo.all(from(a in CardApplication, where: a.idempotency_key == "repeat-me"))

      assert cleared?(id)
    end

    # Sabotage: dropped `a.email != ""` from the purge's query -> red, the
    # second sweep counts the already-cleared application again.
    test "a second sweep with the same clock clears nothing" do
      application("twice", "sent", age(PurgeJob, :sent_after_days) + 1)

      assert {:ok, %{"riverbend" => %{"sent" => 1}}} = PurgeJob.purge(@now)
      assert {:ok, %{"riverbend" => %{"sent" => 0}}} = PurgeJob.purge(@now)
    end
  end

  describe "the engine's own prune" do
    # An execution ended at `ended_at`, with a position blob still stored.
    defp ended_execution(execution_id, ended_at) do
      {:ok, %Storage{opts: opts}} = Storage.new(Persistence, [])

      record = %{
        execution_id: execution_id,
        status: :active,
        content_hash: "sha256:retention-test",
        identity_blob: <<1, 2, 3>>,
        position_blob: <<7, 8, 9>>,
        failure: nil,
        metadata: %{}
      }

      :ok = Persistence.insert_execution(opts, record)

      :ok =
        Persistence.update_execution(
          opts,
          %{record | status: :completed} |> Map.put(:ended_at, ended_at)
        )

      execution_id
    end

    defp position_blob(execution_id) do
      {:ok, %Storage{opts: opts}} = Storage.new(Persistence, [])
      {:ok, %{position_blob: blob}} = Persistence.fetch_execution(opts, execution_id)
      blob
    end

    # Sabotage: made `StatifierExamples.Persistence.prune_executions/4`
    # answer an error instead of delegating -> red, the prune answers
    # that error and clears nothing.
    test "the app's store prunes, without a scope, every execution ended past the age" do
      days = age(PruneJob, :ended_after_days)
      old = ended_execution("retention-old", days_before(days + 1))
      recent = ended_execution("retention-recent", days_before(days - 1))

      assert {:ok, %{executions: 1, position_blobs: 1}} = PruneJob.prune(@now)

      assert position_blob(old) == nil
      assert position_blob(recent) == <<7, 8, 9>>
    end
  end

  describe "the router's reapers" do
    # Sabotage: made `AddressReaper.bindings/0` answer the routed recipe's
    # bindings alone -> red, the card application's address is deleted an
    # hour after its execution finished.
    test "the address reaper keeps a card application's address for its binding's horizon" do
      now = DateTime.utc_now()
      kept = ended_execution("retention-kept", days_before(1 / 24, now))
      due = ended_execution("retention-due", days_before(4, now))

      Repo.insert_all(Address, [
        address_row("1", kept, days_before(1 / 24, now)),
        address_row("2", due, days_before(4, now))
      ])

      assert :ok = AddressReaper.perform(%Oban.Job{})

      assert [^kept] =
               Repo.all(
                 from(a in Address,
                   where: a.document == ^FormPost.Router.document_id(),
                   select: a.execution_id
                 )
               )
    end

    # Sabotage: removed `StatifierExamples.FormPost.PruneJob` from the
    # crontab -> red, the worker is missing.
    test "the purge, the prune and the router's two reapers share the app's crontab" do
      crontab =
        :statifier_examples
        |> Application.fetch_env!(Oban)
        |> Keyword.fetch!(:plugins)
        |> Enum.find_value(fn
          {Oban.Plugins.Cron, opts} -> Keyword.fetch!(opts, :crontab)
          _plugin -> nil
        end)

      workers = Enum.map(crontab, &elem(&1, 1))

      for worker <- [PurgeJob, PruneJob, DedupeReaper, AddressReaper] do
        assert worker in workers
      end
    end
  end

  defp address_row(key, execution_id, terminal_seen_at) do
    %{
      scope: "riverbend",
      document: FormPost.Router.document_id(),
      key: key,
      execution_id: execution_id,
      terminal_seen_at: terminal_seen_at,
      inserted_at: terminal_seen_at
    }
  end
end
