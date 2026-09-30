defmodule StatifierExamplesWeb.RawBody do
  @moduledoc """
  The body reader `Plug.Parsers` uses in `StatifierExamplesWeb.Endpoint`,
  which keeps the raw body of a request under `/basichttp` in
  `conn.private[:raw_body]`.

  A BasicHTTP POST is usually a form body, which `Plug.Parsers` reads and
  decodes before any controller runs, and `StatifierRouter.BasicHTTP.Front`
  needs the body as it arrived. Every other path reads as before.
  """

  @doc "Reads the body as `Plug.Conn.read_body/2` does, keeping it on a `/basichttp` path."
  @spec read_body(Plug.Conn.t(), keyword()) ::
          {:ok, binary(), Plug.Conn.t()} | {:more, binary(), Plug.Conn.t()} | {:error, term()}
  def read_body(%Plug.Conn{path_info: ["basichttp" | _]} = conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} -> {:ok, body, keep(conn, body)}
      {:more, body, conn} -> {:more, body, keep(conn, body)}
      other -> other
    end
  end

  def read_body(conn, opts), do: Plug.Conn.read_body(conn, opts)

  defp keep(conn, body) do
    Plug.Conn.put_private(conn, :raw_body, (conn.private[:raw_body] || "") <> body)
  end
end
