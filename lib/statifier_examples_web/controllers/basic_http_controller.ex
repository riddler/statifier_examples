defmodule StatifierExamplesWeb.BasicHTTPController do
  @moduledoc """
  The BasicHTTP front for `StatifierExamples.HoldDesk`'s durable
  executions: every request at `/basichttp/:token` is handed to
  `StatifierRouter.BasicHTTP.Front.handle/3`, and answered with the
  status and headers `StatifierRouter.BasicHTTP.Front.response/1` maps
  its answer to - 204 for a delivered event or a duplicate, 404 for a
  location that reaches no execution, 405 with `allow: POST` for another
  method, 400 for a body the decoder refuses.

  The token is a bearer capability (ruled by the operator, 2026-09-30):
  holding it is the whole of the authorization, so this action checks
  nothing else. No request line or dispatch log carries it:
  `StatifierExamplesWeb.Endpoint.log_level/1` skips the request line for
  `/basichttp`, the route is `log: false`, and `:filter_parameters` names
  `token`. At `:debug` Ecto's query log prints bound parameters, and the
  router's location lookup binds the token, so a host keeps `:debug` out
  of production.
  """

  use StatifierExamplesWeb, :controller

  alias StatifierExamples.HoldDesk
  alias StatifierRouter.BasicHTTP.Front

  @doc "Hands one request at a location to the front and answers its status."
  @spec event(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def event(conn, _params) do
    {body, conn} = body(conn)

    answer =
      Front.handle(HoldDesk.config(), %{
        token: conn.path_params["token"],
        method: conn.method,
        content_type: header(conn, "content-type"),
        body: body,
        query: if(conn.query_string == "", do: nil, else: conn.query_string),
        send_key: header(conn, "scxml-send-key")
      })

    {status, headers} = Front.response(answer)

    conn
    |> merge_resp_headers(headers)
    |> send_resp(status, "")
  end

  # The body `StatifierExamplesWeb.RawBody` kept when `Plug.Parsers` read
  # it, or the body as it is still waiting, for a content type the parsers
  # passed.
  @spec body(Plug.Conn.t()) :: {binary(), Plug.Conn.t()}
  defp body(%Plug.Conn{private: %{raw_body: body}} = conn), do: {body, conn}

  defp body(conn) do
    case read_body(conn) do
      {:ok, body, conn} -> {body, conn}
      {_more_or_error, _partial, conn} -> {"", conn}
      {:error, _reason} -> {"", conn}
    end
  end

  @spec header(Plug.Conn.t(), String.t()) :: String.t() | nil
  defp header(conn, name), do: conn |> get_req_header(name) |> List.first()
end
