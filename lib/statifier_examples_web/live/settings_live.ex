defmodule StatifierExamplesWeb.SettingsLive do
  @moduledoc """
  `/settings` - a branch library's settings: the three setups it can run,
  each startable on its own.

  The page lists what `StatifierExamples.Library.Setups` lists - a
  catalogue sync, a reading-list import and a card-reader setup - with
  each one's name, what it does and the root outcomes its document
  declares. Pressing a setup's Start starts it as a durable Journey,
  `StatifierExamples.Signup.Journey.start/2` over the setup's own options,
  and sends the reader to the Journey page
  (`StatifierExamplesWeb.SignupJourneyLive`) with the setup's key in
  `?path=` and the new execution's id in `?execution=`. That page walks
  the setup's steps, with Back between them; this one draws no screen of
  its own.

  A setup key the list does not hold is refused on the page rather than
  started, and so is a setup `Journey.start/2` refuses: the reason is
  drawn and nothing is navigated to.
  """

  use StatifierExamplesWeb, :live_view

  alias StatifierBlocks.Document
  alias StatifierExamples.Charts.Durable
  alias StatifierExamples.Library.Setups
  alias StatifierExamples.Signup.Journey

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, assign(socket, setups: setups(), error: nil)}
  end

  @impl Phoenix.LiveView
  def handle_event("start", %{"setup" => key}, socket) do
    with {:ok, opts} <- Setups.options(key),
         {:ok, execution_id} <- Journey.start(Durable.new_execution_id(), opts) do
      {:noreply,
       push_navigate(socket, to: ~p"/signup-journey?#{[path: key, execution: execution_id]}")}
    else
      :error -> {:noreply, assign(socket, error: {:unknown_setup, key})}
      {:error, reason} -> {:noreply, assign(socket, error: reason)}
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
