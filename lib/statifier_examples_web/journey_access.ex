defmodule StatifierExamplesWeb.JourneyAccess do
  @moduledoc """
  Who may see and step a Journey on the Journey page: the access module
  `RiddlerLiveView.Journey` asks before it shows a Journey and before
  every submit, back request and re-present.

  **Interim.** This app has no sign-in and no scope of its own yet, so
  every Journey the page shows is answered under the one fixed scope
  `StatifierExamplesWeb.JourneyHost.scope/0` names, and this module lets
  every actor, signed in or not, take every operation in that scope and in
  no other. It exists so the component mounts at all: the component raises
  at mount without an access module. It goes when the app's Journeys start
  under a scope of their own - a branch library's or a patron's - and the
  app's own access module answers for them.
  """

  @behaviour Riddler.Journey.Access

  alias Riddler.Journey.Scope
  alias StatifierExamplesWeb.JourneyHost

  @doc "`true` for the one fixed scope, whoever asks; `false` for any other."
  @impl Riddler.Journey.Access
  @spec member?(term(), Scope.t()) :: boolean()
  def member?(_actor, scope), do: scope == JourneyHost.scope()

  @doc "The one fixed scope, whoever asks."
  @impl Riddler.Journey.Access
  @spec scopes(term()) :: [Scope.t()]
  def scopes(_actor), do: [JourneyHost.scope()]
end
