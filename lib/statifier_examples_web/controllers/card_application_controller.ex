defmodule StatifierExamplesWeb.CardApplicationController do
  @moduledoc """
  The front of the Riverbend Public Library's card application form:
  `POST /form-post/card-applications`, a form body (urlencoded or JSON)
  under `card_application`.

  The action stores the post and answers before any workflow runs: 202
  with the stored application's id for a new application or a repeat of a
  client key already stored, and 422 with the field errors for a form that
  cannot be stored. The client's key is the form's own `idempotency_key`
  field, which the page that renders the form fills once, so a visitor who
  presses submit twice, or a browser that resends, posts the same key.

  The route takes no browser pipeline: it has no session and no CSRF
  token, because a public form endpoint has no signed-in visitor to
  protect. A host guards it otherwise - an `Origin` check against its own
  pages, a rate limit per client address, a honeypot field that a person
  never fills - and none of that is in this example.

  The library system the form belongs to is fixed here. A multi-tenant
  host resolves it from the request instead (the host name, or the path a
  library system's page posts to), and never from a field the visitor
  could change.
  """

  use StatifierExamplesWeb, :controller

  alias StatifierExamples.FormPost.CardApplications

  @scope "riverbend"

  @doc "Stores one posted card application and answers 202, or 422 with the field errors."
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, params) do
    case CardApplications.receive_application(@scope, form(params)) do
      {:ok, application, _created_or_repeat} ->
        conn
        |> put_status(:accepted)
        |> json(%{application_id: application.id, status: application.status})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: errors(changeset)})
    end
  end

  # The form is the body's `card_application` map; a body without one is
  # an empty form, refused for its missing fields.
  @spec form(map()) :: map()
  defp form(%{"card_application" => %{} = form}), do: form
  defp form(_params), do: %{}

  @spec errors(Ecto.Changeset.t()) :: %{atom() => [String.t()]}
  defp errors(changeset), do: Ecto.Changeset.traverse_errors(changeset, &message/1)

  @spec message({String.t(), keyword()}) :: String.t()
  defp message({message, opts}) do
    Enum.reduce(opts, message, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end
end
