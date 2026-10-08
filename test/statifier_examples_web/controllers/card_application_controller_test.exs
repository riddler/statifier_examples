defmodule StatifierExamplesWeb.CardApplicationControllerTest do
  @moduledoc """
  The card application form's front: `POST /form-post/card-applications`
  stores the post, answers 202 with the stored row's id, and refuses a body
  it cannot store with 422 and the field errors.
  """

  use StatifierExamplesWeb.ConnCase
  # The engine and notifier are named because `Oban.Testing` builds its
  # own config, whose defaults are Postgres'; this app's Oban is SQLite's.
  use Oban.Testing,
    repo: StatifierExamples.Repo,
    engine: Oban.Engines.Lite,
    notifier: Oban.Notifiers.PG

  alias StatifierExamples.FormPost.{CardApplication, IntakeJob}
  alias StatifierExamples.Repo

  @form %{
    "name" => "Hollis Fenwick",
    "email" => "hollis.fenwick@example.com",
    "phone" => "555-0187",
    "street_address" => "4 Orchard Row",
    "wants_card" => "true",
    "wants_newsletter" => "true",
    "idempotency_key" => "form-c1d2"
  }

  # Sabotage: made `create/2` answer 201; this went red on the 202. Reverted.
  test "a form post is stored, answered 202 with its id, and its intake job enqueued", %{
    conn: conn
  } do
    conn = post(conn, ~p"/form-post/card-applications", %{"card_application" => @form})

    assert %{"application_id" => id, "status" => "received"} = json_response(conn, 202)

    assert %CardApplication{scope: "riverbend", email: "hollis.fenwick@example.com"} =
             Repo.get!(CardApplication, id)

    assert_enqueued(worker: IntakeJob, args: %{"application_id" => id})
  end

  # Sabotage: made `create/2` answer a repeat with 200 rather than 202;
  # this went red on the second post's 202. Reverted.
  test "a repeated post answers 202 with the first application's id", %{conn: conn} do
    first = post(conn, ~p"/form-post/card-applications", %{"card_application" => @form})
    assert %{"application_id" => id} = json_response(first, 202)

    again =
      post(build_conn(), ~p"/form-post/card-applications", %{
        "card_application" => Map.put(@form, "name", "A Second Try")
      })

    assert %{"application_id" => ^id} = json_response(again, 202)
    assert Repo.aggregate(CardApplication, :count) == 1
    assert [%Oban.Job{}] = all_enqueued(worker: IntakeJob)
  end

  # Sabotage: dropped `:json` from the endpoint's `Plug.Parsers`, so the
  # JSON body reached the action unparsed; this went red on the 202.
  # Reverted.
  test "a JSON body is accepted the same way", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/form-post/card-applications", Jason.encode!(%{"card_application" => @form}))

    assert %{"application_id" => id} = json_response(conn, 202)
    assert %CardApplication{name: "Hollis Fenwick"} = Repo.get!(CardApplication, id)
  end

  # Sabotage: made `create/2`'s refusal clause answer 202 with an empty
  # body; this went red on the 422. Reverted.
  test "a refused body answers 422 with the field errors and stores nothing", %{conn: conn} do
    conn =
      post(conn, ~p"/form-post/card-applications", %{
        "card_application" =>
          Map.merge(@form, %{
            "email" => "",
            "wants_card" => "false",
            "wants_newsletter" => "false"
          })
      })

    assert %{"errors" => errors} = json_response(conn, 422)

    assert %{
             "email" => ["can't be blank"],
             "wants_card" => ["choose a library card, the newsletter, or both"]
           } = errors

    assert Repo.aggregate(CardApplication, :count) == 0
    assert [] = all_enqueued(worker: IntakeJob)
  end

  # Sabotage: made `create/2` take the top-level params as the form when
  # `card_application` is absent; this went red on the 422. Reverted.
  test "a body without the card_application form answers 422, even with the fields at the top", %{
    conn: conn
  } do
    conn = post(conn, ~p"/form-post/card-applications", @form)

    assert %{"errors" => %{"name" => ["can't be blank"]}} = json_response(conn, 422)
    assert Repo.aggregate(CardApplication, :count) == 0
  end
end
