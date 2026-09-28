defmodule StatifierExamples.Charts.PatronRegistrationTest do
  @moduledoc """
  The patron registration, run: a new patron has a week to verify their
  email address, and when the week runs out the registration ends there.

  The deadline rule abandons the verification group, and the group is the
  root's last step - the age branch and the welcome sit inside its body,
  after the email step - so abandoning it ends the document. Before, the
  branch and the welcome followed the group, and an abandoned registration
  went on to decide the patron's age and welcome them anyway.

  Not async: durable executions step through the application's named
  `StatifierExamples.Charts.ExecutionLock`, and the deadline is a stored
  job.
  """

  use ExUnit.Case, async: false

  import Ecto.Query, only: [from: 2]

  alias Ecto.Adapters.SQL.Sandbox
  alias StatifierExamples.Charts
  alias StatifierExamples.Charts.{Durable, Execution, Timers}
  alias StatifierExamples.Repo
  alias StatifierPersistence.Storage

  @key "patron_registration"
  @deadline "registration.deadline"

  setup do
    :ok = Sandbox.checkout(Repo)

    %{execution_id: "registration-#{System.unique_integer([:positive])}"}
  end

  defp start!(execution_id) do
    {:ok, fixture} = Charts.fixture(@key)
    {:ok, compiled} = Durable.compile(fixture.document, fixture.declare)
    {:ok, driven} = Durable.start(compiled, fixture.document, execution_id, @key)

    driven
  end

  # Every block id the reading says was entered, in order.
  defp entered(%Execution{} = run) do
    for %{kind: :entered, detail: detail} <- Execution.entries(run),
        id <- String.split(detail, ", "),
        do: id
  end

  # Whether the rule reached its own end: its outcome is in the reading.
  # Entering it proves nothing - a rule on the group's rail is entered
  # with the group.
  defp ruled?(%Execution{} = run, rule) do
    Enum.any?(Execution.entries(run), &(&1.kind == :outcome and &1.detail == "done on " <> rule))
  end

  defp deadline_jobs(execution_id) do
    Repo.all(
      from(job in "oban_jobs",
        where: job.worker == "StatifierOban.Timer.Worker",
        select: %{args: job.args, state: job.state}
      )
    )
    |> Enum.map(fn %{args: args} = job ->
      %{job | args: if(is_binary(args), do: Jason.decode!(args), else: args)}
    end)
    |> Enum.filter(&(&1.args["scope"] == execution_id and &1.args["event"] == @deadline))
  end

  defp status!(execution_id) do
    {:ok, store} = Storage.new(StatifierExamples.Persistence, [])
    {:ok, record} = Storage.fetch_execution(store, execution_id)

    record.status
  end

  # The week runs out: the stored deadline job fires, the rule abandons the
  # group, and the execution finishes without entering the age branch or
  # sending the welcome.
  #
  # Sabotage: moved blk_pr_age and blk_pr_welcome back out after the group
  # in the fixture; the fired deadline entered blk_pr_age and this went red.
  # Restored from a copy.
  test "the deadline ends the registration before the age branch", %{
    execution_id: execution_id
  } do
    start!(execution_id)
    :ok = Phoenix.PubSub.subscribe(StatifierExamples.PubSub, Durable.topic(execution_id))

    assert [%{state: "scheduled"}] = deadline_jobs(execution_id)
    assert %{success: 1} = Oban.drain_queue(queue: Timers.queue(), with_scheduled: true)

    assert_receive {:execution_advanced, ^execution_id,
                    {%Durable{}, %Execution{status: :done} = run}}

    assert Enum.any?(Execution.entries(run), &(&1.kind == :event and &1.detail == @deadline))
    assert ruled?(run, "blk_pr_expired")
    refute "blk_pr_age" in entered(run)
    refute "blk_pr_welcome" in entered(run)
    assert status!(execution_id) == :completed
  end

  # The other half, so the refutes above can fail: a verified email inside
  # the week goes on to the age branch and the welcome, and leaving the
  # group takes the deadline down.
  #
  # Sabotage: removed blk_pr_age and blk_pr_welcome from the fixture's
  # group body; the verified patron never entered blk_pr_age and this went
  # red. Restored from a copy.
  test "a verified email inside the week goes on to the age branch and the welcome", %{
    execution_id: execution_id
  } do
    {durable, run} = start!(execution_id)

    assert {:ok, {_durable, run}} = Durable.send_event(durable, run, "email.verified")

    assert run.status == :done
    assert "blk_pr_age" in entered(run)
    assert "blk_pr_welcome" in entered(run)
    refute ruled?(run, "blk_pr_expired")
    assert [%{state: "cancelled"}] = deadline_jobs(execution_id)
  end
end
