defmodule StatifierExamplesWeb.RunFeed do
  @moduledoc """
  The drawer tab this app contributes: the feed of one run, and the buttons
  that step it.

  The run it draws is a `StatifierExamples.Charts.Run` reading and it does
  not care what produced one - a durable run stepped through storage and an
  in-memory session fold render identically here, which is the point of the
  reading being a struct rather than a view of a process.

  ## Why it belongs in the drawer at all

  ADR-0005's 1A test for the drawer is *tabular, and about the whole
  document*. The 2026-08-30 amendment that made the tab strip a host seam
  transfers that test to the host for the tabs it contributes, so this
  panel has to pass it rather than inherit a pass. It does, on both halves:
  a run feed is a grid of rows with the same three columns throughout, and
  a run is about the whole document - it starts at the root, walks whatever
  the chart walks, and finishes at the top-level final. Nothing here is
  about the selected block, which is the line 3A draws between this drawer
  and the inspector.

  The event buttons sit in the same panel and are the one thing that is not
  a row. They are the run's own controls, they are per-document rather than
  per-block (the names come off the document's `core.on_event` blocks), and
  putting them anywhere else would mean a reader watching the feed has to
  look away from it to advance the run.

  ## The markup is the host's

  The package calls `content` and draws whatever comes back; every class
  here is a `myapp-` class this app's own `assets/css/app.css` styles. The
  seam carries no styling of its own and should not: what a host's tab
  looks like is the host's business, exactly as its header is.

  The buttons carry no `phx-target`, so their events reach the LiveView
  rather than the editor component they are rendered inside. That is the
  intended direction - the run is the host's, and the editor knows nothing
  about it beyond the marks and the descriptors it is handed.

  ## The one sharp edge in the seam

  The package calls `content` with `%{id:, count:}` and nothing else, so the
  run this panel draws arrives through the closure's captured environment,
  where LiveView's change tracking cannot see it. A caller that merges its
  own data in with `Map.merge/2` leaves `__changed__` naming only `id` and
  `count`, and every dynamic in the markup below that reads `@run` is then
  diffed as unchanged - the panel renders correctly the first time the tab
  is opened and never moves again, while the tab's own count keeps climbing
  beside it. `StatifierExamplesWeb.EditorLive` therefore merges with
  `Phoenix.Component.assign/2`, which is what marks the keys changed. It is
  one line, and the failure it avoids is silent.
  """

  use Phoenix.Component

  alias StatifierExamples.Charts.Run

  attr :id, :string, required: true
  attr :count, :integer, default: nil
  attr :run, :any, required: true
  attr :events, :list, default: []

  @doc """
  The panel: the run's status and its event buttons, then its rows.

  Run and Stop are **not** here. They are in the host's header beside
  Compile, because a control that can only be reached by opening the drawer
  is a control nobody finds - and because starting a run is the same kind of
  act as compiling one, which is what the header is already for. What stays
  here is what is about a run in progress: the events it will accept, and
  what it has done.

  `run` is `nil` before anything has been started, and the panel says so
  rather than rendering an empty table - a grid with a header and no rows
  reads as "the run produced nothing", which is a different fact.
  """
  @spec panel(map()) :: Phoenix.LiveView.Rendered.t()
  def panel(assigns) do
    ~H"""
    <div class="myapp-runs" id={"#{@id}-panel-body"}>
      <div class="myapp-runs__controls">
        <span class="myapp-runs__status">
          {status_label(@run)}
        </span>

        <button
          :for={event <- @events}
          class="myapp-runs__button myapp-runs__button--event"
          type="button"
          disabled={is_nil(@run) or @run.status != :running}
          phx-click="run-send"
          phx-value-event={event}
        >
          {event}
        </button>
      </div>

      <p :if={is_nil(@run)} class="myapp-runs__empty">
        Nothing is running. Run, in the header, starts a session on this document in memory.
      </p>

      <table :if={@run} class="myapp-runs__table">
        <thead>
          <tr>
            <th class="myapp-runs__seq" scope="col">#</th>
            <th scope="col">What</th>
            <th scope="col">Detail</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={entry <- Run.entries(@run)} data-run-entry={entry.kind}>
            <td class="myapp-runs__seq">{entry.seq}</td>
            <td class="myapp-runs__what">{entry.label}</td>
            <td class="myapp-runs__detail">{entry.detail}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @spec status_label(term()) :: String.t()
  defp status_label(nil), do: "no run"
  defp status_label(run), do: to_string(run.status)
end
