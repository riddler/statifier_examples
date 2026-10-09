defmodule StatifierExamples.FormPost.PurgeJob do
  @moduledoc """
  The host's retention for the card applications it stores: an Oban job,
  on this app's crontab, that clears the personal fields of an application
  once its outcome is old enough.

  The posted values live in the host's `card_applications` table and
  nowhere else, so how long they stay is the host's decision, not the
  engine's. No state chart holds a timer per application for it: one job
  on the app's own scheduler sweeps the table instead.

  For each library system the app serves, the job clears the personal
  fields (the name, the email address, the phone number and the street
  address) of:

  - a screened-out application (`status` `"screened_out"`) whose
    `updated_at` is older than `:screened_out_after_days`;
  - a sent application (`status` `"sent"`) whose `updated_at` is older
    than `:sent_after_days`.

  It clears the fields and keeps the row, rather than deleting it: the
  row's id and the client's idempotency key stay, so a repeat post of the
  same form is still matched by the `(scope, idempotency_key)` unique index
  and answers the first application instead of storing the values again.
  The write is `StatifierExamples.FormPost.CardApplications.Writer`'s, the
  one module that updates a stored application.

  An application is marked `"screened_out"` by
  `StatifierExamples.FormPost.Delivery` when the screen's answer ends its
  execution screened out, and `"sent"` by the routes; each stamps
  `updated_at` as it does, so the age is measured from the outcome.

  The ages are application config, in days, under this module's name in
  `config/config.exs`; the values there are this example's, not a
  recommendation. `perform/1` reads the clock and hands it to `purge/1`,
  which a test calls with a clock of its own.
  """

  use Oban.Worker, queue: :retention

  alias StatifierExamples.FormPost.CardApplications.Writer
  alias StatifierExamples.FormPost.Steps

  @typedoc "How many applications one sweep cleared, per library system and status."
  @type counts :: %{String.t() => %{String.t() => non_neg_integer()}}

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    {:ok, _counts} = purge(DateTime.utc_now())
    :ok
  end

  @doc """
  Clears the personal fields of every application whose outcome is older
  than its configured age at `now`, in every library system the app
  serves, and answers what it cleared.
  """
  @spec purge(DateTime.t()) :: {:ok, counts()}
  def purge(%DateTime{} = now) do
    ages = [
      {"screened_out", age!(:screened_out_after_days)},
      {"sent", age!(:sent_after_days)}
    ]

    counts =
      Map.new(library_systems(), fn scope ->
        {scope,
         Map.new(ages, fn {status, days} ->
           {:ok, count} = Writer.purge_personal_fields(scope, status, cutoff(now, days))
           {status, count}
         end)}
      end)

    {:ok, counts}
  end

  # The library systems this app stores applications under: one, the one
  # the form's controller fixes. A host serving several sweeps each.
  @spec library_systems() :: [String.t()]
  defp library_systems, do: [Steps.library_system()]

  @spec cutoff(DateTime.t(), pos_integer()) :: DateTime.t()
  defp cutoff(now, days), do: DateTime.add(now, -days * 86_400, :second)

  @spec age!(atom()) :: pos_integer()
  defp age!(key) do
    case :statifier_examples |> Application.fetch_env!(__MODULE__) |> Keyword.fetch!(key) do
      days when is_integer(days) and days > 0 ->
        days

      other ->
        raise ArgumentError,
              "#{inspect(key)} must be a positive number of days, got: #{inspect(other)}"
    end
  end
end
