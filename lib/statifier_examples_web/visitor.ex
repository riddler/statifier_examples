defmodule StatifierExamplesWeb.Visitor do
  @moduledoc """
  Who the browser is, as far as this app knows: the plug in the `:browser`
  pipeline that puts the two session keys
  `StatifierExamplesWeb.JourneyAccess.actor/1` reads.

  This app has no sign-in, so the session is the whole of an identity:

    * `"visitor"` - an id minted for the session on its first request and
      kept for as long as the session cookie is. It names the patron a
      visitor's own registration is about to create
      (`StatifierExamplesWeb.JourneyAccess`'s "The patron scope").
    * `"librarian_of"` - the id of the branch library the session's visitor
      is librarian of. Nothing in the app signs a librarian in: the plug
      puts the branch this module's configuration names, `librarian_of:`,
      into a session that has none, and the dev configuration names
      `"riverside"`, so the dev server's settings page and branch
      onboarding work for whoever opens them. The test configuration names
      none, and a test that needs a librarian puts the key in its own
      session. The prod configuration names none either, so a prod build
      makes no session a librarian: every visitor holds its own patron
      scope and the open scope and nothing else, so a start of the branch
      onboarding or of a setup draws the one refusal for everyone. A
      deployment that wants librarians signs them in and puts the key in
      the session before this plug runs; this app has no sign-in to do it.

  Neither key is written over once it is there.
  """

  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    conn
    |> put_new("visitor", fn -> 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64() end)
    |> put_new("librarian_of", &configured_branch/0)
  end

  @spec put_new(Plug.Conn.t(), String.t(), (-> String.t() | nil)) :: Plug.Conn.t()
  defp put_new(conn, key, value) do
    with nil <- get_session(conn, key),
         new when is_binary(new) <- value.() do
      put_session(conn, key, new)
    else
      _kept_or_none -> conn
    end
  end

  @spec configured_branch() :: String.t() | nil
  defp configured_branch,
    do: :statifier_examples |> Application.get_env(__MODULE__, []) |> Keyword.get(:librarian_of)
end
