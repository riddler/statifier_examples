defmodule StatifierExamplesWeb.SignupScreensLive do
  @moduledoc """
  `/signup-screens` - the walking skeleton's page: one resolved signup screen,
  drawn by `StatifierExamplesWeb.SignupElements` from
  `priv/fixtures/signup_screens.json`.

  The page exists because function components that nothing renders are
  components nobody has checked. There is no chart behind it yet: answers are
  held in the socket, and an outcome is displayed rather than sent anywhere.
  `se-19h` puts the screen Composite underneath, and the outcome a button
  names here is the outcome slot it fills there - which is why this page
  stores the outcome instead of acting on it.

  `?screen=<key>` picks the screen; the first one is the default.
  """

  use StatifierExamplesWeb, :live_view

  alias StatifierExamples.Signup.Screens
  alias StatifierExamplesWeb.SignupElements

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, assign(socket, answers: %{}, outcome: nil, screens: Screens.screens())}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    screens = socket.assigns.screens
    requested = params["screen"]
    screen = Enum.find(screens, hd(screens), &(&1.key == requested))

    {:noreply, assign(socket, screen: screen)}
  end

  @impl Phoenix.LiveView
  def handle_event("answer", %{"answers" => answers}, socket) do
    {:noreply, assign(socket, answers: Map.merge(socket.assigns.answers, answers))}
  end

  def handle_event("outcome", %{"outcome" => outcome}, socket) do
    {:noreply, assign(socket, outcome: outcome)}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    assigns = assign(assigns, datamodel: %{"answers" => coerce(assigns.answers)})

    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto flex max-w-xl flex-col gap-6 p-6">
        <nav class="flex gap-2" aria-label="Screens">
          <.link
            :for={screen <- @screens}
            patch={~p"/signup-screens?screen=#{screen.key}"}
            class={["btn btn-sm", screen.key == @screen.key && "btn-active"]}
          >
            {screen.title}
          </.link>
        </nav>

        <form id="signup-answers" phx-change="answer" class="contents">
          <SignupElements.resolved_screen screen={@screen} datamodel={@datamodel} />
        </form>

        <p :if={@outcome} id="last-outcome" class="text-sm opacity-70">
          Last outcome: <code>{@outcome}</code>
        </p>
      </div>
    </Layouts.app>
    """
  end

  # Answers arrive from the form as strings. A condition like
  # `answers.seats > 1` needs the number, and predicator will not compare a
  # string to an integer, so a value that is entirely digits is read as one.
  # Coercing at the edge rather than in the resolver keeps the resolver's
  # contract simple: it evaluates against whatever datamodel it is handed,
  # and a chart-backed page (se-19h) will hand it typed values already.
  @spec coerce(%{optional(String.t()) => String.t()}) :: map()
  defp coerce(answers) do
    Map.new(answers, fn
      {key, value} when is_binary(value) ->
        case Integer.parse(value) do
          {number, ""} -> {key, number}
          _not_an_integer -> {key, value}
        end

      {key, value} ->
        {key, value}
    end)
  end
end
