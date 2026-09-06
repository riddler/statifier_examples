defmodule StatifierExamples.Repo.Migrations.CreateInviteOutcomes do
  @moduledoc """
  The data plane's own table: one row per invitee a bulk chunk handler
  processed (se-j87).

  It exists to make the boundary rule visible in the schema. The chart
  orchestrates batches, so a fan-out's parent holds ten chunk descriptors
  and the assembled ten summaries and nothing else; the data plane
  processes rows, so the rows land here, in a table the host owns and the
  engine has never heard of. Nothing the chart owns is duplicated into it.

  `chunk_id` and `email` together are the natural key. A chunk start job
  is at-least-once like every other job, so a redelivered chunk has to
  write the same rows rather than a second set of them, and the unique
  index is what makes the upsert that does it possible - the same
  mechanism `StatifierExamples.Signup.Accounts` provisions an account
  with, for the same reason.

  `run_id` is the chunk child's own run, so a reader with a row can open
  the run that wrote it. `promoted_run_id` is null for every row but the
  one whose processing had to wait on a person: that row got a run of its
  own, and this column is where the two halves of the boundary rule meet.
  """

  use Ecto.Migration

  def change do
    create table(:invite_outcomes) do
      add(:chunk_id, :string, null: false)
      add(:email, :string, null: false)
      add(:status, :string, null: false)
      add(:run_id, :string, null: false)
      add(:promoted_run_id, :string)

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:invite_outcomes, [:chunk_id, :email]))
  end
end
