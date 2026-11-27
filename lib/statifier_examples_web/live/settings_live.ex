defmodule StatifierExamplesWeb.SettingsLive do
  @moduledoc """
  `/settings` - a branch library's settings: the three setups it can run,
  each startable on its own.

  The page lists what `StatifierExamples.Library.Setups` lists - a
  catalogue sync, a reading-list import and a card-reader setup - with
  each one's name, what it does and the root outcomes its document
  declares. Pressing a setup's Start starts it alone as a durable Journey
  under the librarian's branch scope, through
  `StatifierExamplesWeb.JourneyHost.start/2`, and sends the reader to the
  Journey page
  (`StatifierExamplesWeb.SignupJourneyLive`) with the setup's key in
  `?path=` and the new execution's id in `?execution=`. That page walks
  the setup's steps, with Back between them; this one draws no screen of
  its own.

  A setup key the list does not hold is refused on the page rather than
  started: the reason is drawn and nothing is navigated to.

  ## Whose settings

  The page is a librarian's. The branch scope a setup starts under is the
  one of the branch the session's visitor is librarian of
  (`StatifierExamplesWeb.JourneyAccess.start_scope/2`), asked of the access
  module before the host starts it, and the setup's execution records it.
  A visitor who is no librarian holds no branch scope, so its Start draws
  the one refusal and starts nothing; the list itself is the same for
  every visitor, since it says only what a branch can run.
  """

  use StatifierExamplesWeb, :live_view

  alias Riddler.Journey.Access
  alias StatifierBlocks.Document
  alias StatifierExamples.Library.Setups
  alias StatifierExamplesWeb.{JourneyAccess, JourneyHost}

  @impl Phoenix.LiveView
  def mount(_params, session, socket) do
    {:ok,
     assign(socket,
       actor: JourneyAccess.actor(session),
       setups: setups(),
       error: nil,
       refused: false
     )}
  end

  @impl Phoenix.LiveView
  def handle_event("start", %{"setup" => key}, socket) do
    case Setups.options(key) do
      {:ok, _opts} -> {:noreply, start(socket, key)}
      :error -> {:noreply, assign(socket, error: {:unknown_setup, key}, refused: false)}
    end
  end

  # Starts the setup `key` under the librarian's branch scope (the
  # moduledoc's "Whose settings").
  @spec start(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  defp start(socket, key) do
    actor = socket.assigns.actor

    with {:ok, scope} <- JourneyAccess.start_scope("branch", actor),
         :ok <- Access.check(JourneyAccess, actor, scope, :present),
         {:ok, journey, _answer} <- JourneyHost.start(key, scope),
         {:ok, ^key, execution_id} <- JourneyHost.parse(journey) do
      push_navigate(socket, to: ~p"/signup-journey?#{[path: key, execution: execution_id]}")
    else
      _refused -> assign(socket, error: nil, refused: true)
    end
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto flex max-w-xl flex-col gap-6 p-6">
        <h1 class="text-sm font-semibold uppercase tracking-wide opacity-60">Branch settings</h1>

        <p :if={@error} id="settings-error" class="alert alert-error text-sm">
          {inspect(@error)}
        </p>

        <p :if={@refused} id="settings-refused" class="text-sm" data-riddler-refused>
          {JourneyAccess.refused_text()}
        </p>

        <ul class="flex flex-col gap-4">
          <li :for={setup <- @setups} id={"setup-#{setup.key}"} class="flex flex-col gap-2">
            <h2 class="font-medium">{setup.name}</h2>
            <p class="text-sm text-base-content/70">{setup.description}</p>
            <p class="text-xs opacity-70">
              Finishes with <code :for={outcome <- setup.outcomes}>{outcome}</code>
            </p>
            <button
              id={"start-#{setup.key}"}
              type="button"
              class="btn btn-sm self-start"
              phx-click="start"
              phx-value-setup={setup.key}
            >
              Start
            </button>
          </li>
        </ul>
      </div>
    </Layouts.app>
    """
  end

  # What the page draws of each setup, read from its document once at
  # mount.
  @spec setups() :: [map()]
  defp setups do
    for key <- Setups.keys() do
      {:ok, %Document{metadata: metadata}} = Setups.document(key)
      {:ok, outcomes} = Setups.outcomes(key)

      %{
        key: key,
        name: Map.get(metadata, "name", key),
        description: Map.get(metadata, "description", ""),
        outcomes: outcomes
      }
    end
  end
end
