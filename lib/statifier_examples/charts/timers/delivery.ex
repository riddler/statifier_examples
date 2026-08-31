defmodule StatifierExamples.Charts.Timers.Delivery do
  @moduledoc """
  How a fired timer job gets back into a durable run.

  `StatifierOban.Timer.Delivery` is a behaviour precisely because whether
  a run is live is the host's question. The package's default answers it
  from `Statifier.Session`'s registry, and this app has no session
  process to look up: its runs live in SQLite between steps and are
  driven by whichever process happens to be holding the page. So the
  answer here is the stored run's own status, and the feed-back is one
  more drive of `StatifierExamples.Charts.Durable`.

  Nothing about this module knows a page exists. It is handed a run id
  and an effect by an Oban worker, on a node that may have started after
  the timer was armed, and everything it needs to rebuild the chart it
  reads back out of storage. That is what "the reminder survives a
  restart" means in code.

  ## Discarding, and why it is the ordinary answer

  Spec 6.2 says a delayed send whose session ended before the delay
  elapsed is discarded without delivery, and st-ADR-0054 decision 4 makes
  enforcing that the delivery seam's job. A run that finished, was
  abandoned by the host, or was never stored is therefore
  `{:discarded, reason}` - which the worker records on the job row as a
  cancellation, so the discard is visible rather than silent.

  A chart this app can no longer rebuild is a discard too, with the
  reason saying which half is missing: a run whose record carries no
  fixture key (one started from a document that is not a shipped
  fixture), a key nothing registers any more, or a document edited since
  the run started - the last arriving as the storage layer's own
  `{:identity_mismatch, _, _}`. None of them is fixable by retrying, and
  all of them are facts about the run rather than about the node, which
  is the line `StatifierOban.Timer.Worker` draws between a cancel and a
  retry.
  """

  @behaviour StatifierOban.Timer.Delivery

  alias Statifier.Effect.SendDelayed
  alias StatifierExamples.Charts.Durable

  @doc """
  Feeds `effect`'s event back into the run named by `scope`, if it is
  still live.
  """
  @impl StatifierOban.Timer.Delivery
  def deliver(scope, %SendDelayed{event: event}) when is_binary(scope) do
    Durable.deliver(scope, event)
  end
end
