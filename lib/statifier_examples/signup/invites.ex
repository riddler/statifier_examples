defmodule StatifierExamples.Signup.Invites do
  @moduledoc """
  The data plane of the bulk-invite example: the rows one chunk
  descriptor stands for, and the write that records what happened to each
  of them (se-j87).

  ## The descriptor is the row set

  A `core.map` fans out over **descriptors** - ids, ranges, chunk handles
  - and never over row payloads, because the list it maps over lives in
  the parent run's datamodel and is serialized on every persisted step
  for the rest of the run. A fan-out over ten thousand invitee ids costs
  what ids cost; one over ten thousand invitee records charges the parent
  for those records forever.

  So a descriptor here is a short string, `su-c01` through `su-c10`, and
  the rows it stands for are derived from it rather than carried with it.
  In a deployment the derivation is a query against the upload the chunk
  names; here it is arithmetic, for
  `StatifierExamples.Signup.Accounts`' reason - a deterministic function
  of the descriptor is what makes the write idempotent without a table of
  keys - and every address it produces is fiction, as every value in this
  repo is.

  A descriptor this module does not recognise is `:error` rather than an
  empty row set. A chunk that stands for nothing is a chunk somebody
  mistyped, and answering it with zero rows would report a successful
  batch that processed nothing.

  ## Idempotency

  A chunk's start job is at-least-once, so `record/3` writes with
  `on_conflict: :nothing` against the `{chunk_id, email}` index. A
  redelivered chunk finds its rows already there and writes none, and the
  row count is the same either way.

  ## Promotion

  One invitee in this example needs chart semantics - their signup waits
  on a person, which is exactly the condition the boundary rule names -
  and that row gets a run of its own rather than being processed as data.
  Which invitee is a fact about the descriptor, so `promoted_email/1`
  answers it and `promoted_run_id/1` names the run it is given, both
  deterministically: a redelivered chunk asks for the same run id and the
  storage layer's atomic `:run_exists` refusal is what makes the second
  ask a no-op rather than a second run.
  """

  import Ecto.Query, only: [from: 2]

  alias StatifierExamples.Repo
  alias StatifierExamples.Signup.InviteOutcome

  # How many invitees one chunk descriptor stands for. Small enough that
  # the whole example runs in a test, large enough that ten chunks are
  # visibly a batch rather than a list.
  @rows_per_chunk 25

  # The descriptors this example ships, spelled as a pattern rather than a
  # list: the list itself is authored in the document, which is where a
  # reader should meet it, and repeating it here would be a second place
  # to edit it.
  @descriptor ~r/^su-c(0[1-9]|10)$/

  # The one chunk holding an invitee whose signup has to wait on a person,
  # and that invitee's position in it. Fixed so the example is the same
  # every time it runs.
  @promoted_chunk "su-c07"
  @promoted_row 3

  @doc """
  The invitee addresses `chunk_id` stands for, in order.

  `:error` for a descriptor this example does not ship - see the
  moduledoc on why that is a refusal rather than an empty list.
  """
  @spec rows_for(String.t()) :: {:ok, [String.t()]} | :error
  def rows_for(chunk_id) when is_binary(chunk_id) do
    if Regex.match?(@descriptor, chunk_id) do
      {:ok, Enum.map(1..@rows_per_chunk, &email_for(chunk_id, &1))}
    else
      :error
    end
  end

  @doc """
  The fictional address of row `n` of `chunk_id`.

  Public because it is the key: a test asserting that two deliveries of
  the same chunk wrote one row set needs the derivation the writer used,
  not a copy of it.
  """
  @spec email_for(String.t(), pos_integer()) :: String.t()
  def email_for(chunk_id, n) when is_binary(chunk_id) and is_integer(n) do
    "invitee-#{chunk_id}-#{n}@example.com"
  end

  @doc """
  The address in `chunk_id` whose signup has to wait on a person, or
  `nil` when this chunk holds none.
  """
  @spec promoted_email(String.t()) :: String.t() | nil
  def promoted_email(@promoted_chunk), do: email_for(@promoted_chunk, @promoted_row)
  def promoted_email(chunk_id) when is_binary(chunk_id), do: nil

  @doc """
  The run id a promoted invitee's own run is started under.

  Derived from the descriptor, so a redelivered chunk asks for the same
  run and gets the storage layer's `:run_exists` refusal rather than a
  second one.
  """
  @spec promoted_run_id(String.t()) :: String.t()
  def promoted_run_id(chunk_id) when is_binary(chunk_id), do: "promoted-#{chunk_id}"

  @doc """
  Records every row of `chunk_id` as processed by the run `run_id`, with
  `promoted_run_id` on the one row that got a run of its own.

  Answers how many rows the chunk stands for, which is the same number on
  a first delivery and on a replay. `:error` for an unrecognised
  descriptor, which is what a refused chunk answers the chart with.
  """
  @spec record(String.t(), String.t(), String.t() | nil) :: {:ok, non_neg_integer()} | :error
  def record(chunk_id, run_id, promoted_run_id)
      when is_binary(chunk_id) and is_binary(run_id) do
    with {:ok, emails} <- rows_for(chunk_id) do
      promoted = promoted_email(chunk_id)
      now = DateTime.utc_now()

      entries =
        Enum.map(emails, fn email ->
          %{
            chunk_id: chunk_id,
            email: email,
            status: status(email, promoted),
            run_id: run_id,
            promoted_run_id: promoted_for(email, promoted, promoted_run_id),
            inserted_at: now,
            updated_at: now
          }
        end)

      Repo.insert_all(InviteOutcome, entries,
        on_conflict: :nothing,
        conflict_target: [:chunk_id, :email]
      )

      {:ok, length(entries)}
    end
  end

  @doc "Every recorded row of `chunk_id`, in address order."
  @spec for_chunk(String.t()) :: [InviteOutcome.t()]
  def for_chunk(chunk_id) when is_binary(chunk_id) do
    Repo.all(from(o in InviteOutcome, where: o.chunk_id == ^chunk_id, order_by: o.email))
  end

  @doc "Every recorded row that was given a run of its own."
  @spec promoted() :: [InviteOutcome.t()]
  def promoted do
    Repo.all(from(o in InviteOutcome, where: not is_nil(o.promoted_run_id), order_by: o.email))
  end

  @doc "How many rows have been recorded, across every chunk."
  @spec count() :: non_neg_integer()
  def count, do: Repo.aggregate(InviteOutcome, :count)

  @spec status(String.t(), String.t() | nil) :: String.t()
  defp status(email, email), do: "promoted"
  defp status(_email, _promoted), do: "provisioned"

  @spec promoted_for(String.t(), String.t() | nil, String.t() | nil) :: String.t() | nil
  defp promoted_for(email, email, promoted_run_id), do: promoted_run_id
  defp promoted_for(_email, _promoted, _promoted_run_id), do: nil
end
