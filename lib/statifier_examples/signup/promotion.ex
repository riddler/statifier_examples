defmodule StatifierExamples.Signup.Promotion do
  @moduledoc """
  The other half of the boundary rule: the one row in a batch whose
  processing has to wait on a person, and the run it is given (se-j87).

  A `core.map` fan-out is the chart orchestrating batches. Every invitee a
  chunk stands for is processed as data, in bulk, by one call - and one of
  them is not, because their signup waits for a person to verify an
  address, which is chart semantics and not a row's. That invitee is
  **promoted**: it gets a run of its own, of the signup wizard this app
  already ships, through the host's ordinary entry door.

  ## The ordinary door, and why not a subchart

  `StatifierExamples.Charts.Durable.start/4` is the same call the editor's
  Run button makes. A promoted invitee is therefore a run a reader opens
  by URL like any other, resumes after a `kill -9` like any other, and
  drives to the end like any other - which is the point. It is not a
  durable subchart of the chunk chart, and the difference is deliberate:
  a subchart's lifetime is its parent's, cancelled when the parent is,
  and a batch import that finished should not take a person's half-driven
  signup with it.

  ## Idempotency

  A chunk's start job is at-least-once, so this can be asked twice for the
  same chunk. The run id is derived from the descriptor
  (`StatifierExamples.Signup.Invites.promoted_run_id/1`), so the second
  ask reaches the storage layer's atomic `:run_exists` refusal and is
  reported as `{:existing, run_id}` rather than starting a second run -
  the same shape, and the same honesty, as
  `StatifierExamples.Signup.Accounts.provision/1`'s
  `{:created, _} | {:existing, _}`.
  """

  require Logger

  alias StatifierExamples.Charts
  alias StatifierExamples.Charts.Durable
  alias StatifierExamples.Signup.Invites

  # The document a promoted invitee gets a run of: the wizard this app
  # already ships, by its fixture key, so the run records the same
  # `fixture` metadata every other root run records and a fired timer can
  # rebuild its chart on a cold node.
  @wizard "signup_wizard"

  @typedoc """
  What promoting did: started the run, found the one a previous delivery
  of the same chunk started, or found nothing to promote in this chunk.
  """
  @type outcome :: {:started, String.t()} | {:existing, String.t()} | :none

  @doc """
  Gives the invitee in `chunk_id` that needs chart semantics a run of its
  own, or answers `:none` for a chunk holding no such invitee.

  `{:error, reason}` only for a failure that is not "it already exists":
  a chart this app no longer ships, or a storage layer that could not
  write. Those reach the chunk's bulk call as a refusal, because a
  promotion that silently did not happen would report a batch as fully
  processed when a row of it was not.
  """
  @spec promote(String.t()) :: {:ok, outcome()} | {:error, term()}
  def promote(chunk_id) when is_binary(chunk_id) do
    case Invites.promoted_email(chunk_id) do
      nil -> {:ok, :none}
      email -> start_run(chunk_id, email)
    end
  end

  @spec start_run(String.t(), String.t()) :: {:ok, outcome()} | {:error, term()}
  defp start_run(chunk_id, email) do
    run_id = Invites.promoted_run_id(chunk_id)

    with {:ok, fixture} <- Charts.fixture(@wizard),
         {:ok, compiled} <- Durable.compile(fixture.document, fixture.declare) do
      started(Durable.start(compiled, fixture.document, run_id, @wizard), run_id, email)
    else
      :error -> {:error, :chart_unknown}
      {:error, _findings} = error -> error
    end
  end

  @spec started({:ok, term()} | {:error, term()}, String.t(), String.t()) ::
          {:ok, outcome()} | {:error, term()}
  defp started({:ok, _driven}, run_id, email) do
    Logger.info("promoted #{email} to its own run #{run_id}")

    {:ok, {:started, run_id}}
  end

  # The atomic refusal, not a pre-check: a second delivery of the same
  # chunk asks for the same derived run id and the adapter says the row is
  # already there. That is the promotion being idempotent, so it is an
  # answer rather than an error.
  defp started({:error, :run_exists}, run_id, email) do
    Logger.info("promotion of #{email} found its run #{run_id} already started")

    {:ok, {:existing, run_id}}
  end

  defp started({:error, reason}, _run_id, _email), do: {:error, reason}
end
