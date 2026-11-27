defmodule StatifierExamplesWeb.JourneyAccess do
  @moduledoc """
  Who may see and step a Journey on this app's pages: the access module
  `RiddlerLiveView.Journey` asks before it shows a Journey and before every
  submit, back request and re-present, and the one the Journey page and the
  settings page ask before they start a Journey.

  ## Who is asking

  This app has no sign-in. The actor is read from the browser's session,
  which `StatifierExamplesWeb.Visitor` fills on the first request
  (`actor/1`): the visitor's own id, minted for the session, and the id of
  the branch library the visitor is librarian of, when the session names
  one. The `users` table is not who is asking: it holds the accounts that
  finished signups created, and nobody signs in with one.

  ## The scopes

  | Scope | Its Journeys | Who holds it |
  |---|---|---|
  | `{"branch", id}` | the branch onboarding and the three setups | the librarian of that branch |
  | `{"patron", id}` | patron registration, in either of its forms | the visitor whose session id is `id` |
  | `{"open", "signup"}` | the signup Path | every visitor |

  `scopes/1` lists the scopes an actor holds and `member?/2` answers `true`
  for exactly those, so the two agree as `Riddler.Journey.Access` asks.
  Which kind of scope a Path's Journeys take is
  `StatifierExamplesWeb.JourneyHost.scope_kind/1`'s, and `start_scope/2`
  says which scope of that kind a Journey this actor starts runs under.

  ## The patron scope

  A patron registers itself, and the patron does not exist until the
  registration finishes. So a registration starts under the patron scope
  named by the visitor's own session id: the patron the registration is
  about to create. The visitor walks that registration, and no other
  visitor's: a registration started in another session is answered with
  the one refusal.

  ## What a visitor who is no librarian may do

  Every visitor holds its own patron scope and the open scope, and nothing
  else unless its session names a branch. So a visitor who is no librarian
  may start and walk its own patron registration and the signup Path, and
  is refused, with the one refusal, any branch's Journey: it starts no
  setup and no onboarding, and sees nothing of one a librarian started.

  The signup Path is the app's fixture-only wizard and is open: it signs
  up an account that does not exist yet, as a patron registration does,
  and it keeps no scope of its own beyond the one every visitor holds.

  ## Every member takes every operation

  This module does not export `c:Riddler.Journey.Access.allowed?/3`, so
  every member of a scope may present, submit and go back in its Journeys,
  as `Riddler.Journey.Access.check/4` reads an access module without it.
  Nothing here tells a librarian's operations apart from a patron's.
  """

  @behaviour Riddler.Journey.Access

  alias Riddler.Journey.Scope

  @typedoc """
  Who is asking: the visitor's session id and the branch it is librarian
  of, each `nil` where the session names none.
  """
  @type actor :: %{visitor: String.t() | nil, librarian_of: String.t() | nil}

  # The one sentence drawn in place of a Journey the visitor may not see.
  @refused_text "There is nothing to show here."

  @doc """
  The actor a page's session names (the moduledoc's "Who is asking").

      iex> StatifierExamplesWeb.JourneyAccess.actor(%{"visitor" => "v-1"})
      %{visitor: "v-1", librarian_of: nil}
  """
  @spec actor(map()) :: actor()
  def actor(session) when is_map(session) do
    %{visitor: string(session["visitor"]), librarian_of: string(session["librarian_of"])}
  end

  @doc "The scope every visitor holds, the signup Path's."
  @spec open_scope() :: Scope.t()
  def open_scope do
    {:ok, scope} = Scope.new("open", "signup")
    scope
  end

  @doc """
  The scopes `actor` holds: the open scope, its own patron scope, and the
  branch scope of the branch it is librarian of. An actor that is not one
  `actor/1` gives holds the open scope alone.
  """
  @impl Riddler.Journey.Access
  @spec scopes(term()) :: [Scope.t()]
  def scopes(actor) do
    [open_scope()] ++ held("patron", visitor(actor)) ++ held("branch", librarian_of(actor))
  end

  @doc "`true` for exactly the scopes `scopes/1` lists."
  @impl Riddler.Journey.Access
  @spec member?(term(), Scope.t()) :: boolean()
  def member?(actor, %Scope{} = scope), do: scope in scopes(actor)
  def member?(_actor, _scope), do: false

  @doc """
  The scope of `kind` a Journey `actor` starts runs under: the open scope
  for `"open"`, the actor's own patron scope for `"patron"`, and the branch
  scope of the branch it is librarian of for `"branch"`. `:error` where the
  actor holds no scope of that kind.
  """
  @spec start_scope(String.t(), term()) :: {:ok, Scope.t()} | :error
  def start_scope("open", _actor), do: {:ok, open_scope()}
  def start_scope("patron", actor), do: one(held("patron", visitor(actor)))
  def start_scope("branch", actor), do: one(held("branch", librarian_of(actor)))
  def start_scope(_kind, _actor), do: :error

  @doc """
  The sentence a page draws in place of a Journey the visitor may not see,
  the one `RiddlerLiveView.Journey` is given as its `refused_text`.
  """
  @spec refused_text() :: String.t()
  def refused_text, do: @refused_text

  @spec held(String.t(), String.t() | nil) :: [Scope.t()]
  defp held(_kind, nil), do: []

  defp held(kind, id) do
    case Scope.new(kind, id) do
      {:ok, scope} -> [scope]
      {:error, :invalid_scope} -> []
    end
  end

  defp one([scope]), do: {:ok, scope}
  defp one([]), do: :error

  defp visitor(%{visitor: visitor}), do: visitor
  defp visitor(_actor), do: nil

  defp librarian_of(%{librarian_of: branch}), do: branch
  defp librarian_of(_actor), do: nil

  defp string(value) when is_binary(value) and value != "", do: value
  defp string(_value), do: nil
end
