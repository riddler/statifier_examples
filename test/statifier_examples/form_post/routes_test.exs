defmodule StatifierExamples.FormPost.RoutesTest do
  @moduledoc """
  The card application form's two routes, the patron system and the events
  newsletter list: each takes the application's id from the event, records
  an outbox row of ids and the outside reference, and writes the reference
  back through the one writer. A refusal is an `{:error, reason}` before
  any write, and no value the visitor typed reaches the outbox or a reason.
  """

  # Not async: writes to the repo.
  use StatifierExamplesWeb.ConnCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Statifier.Event

  alias StatifierExamples.FormPost.{
    CardApplication,
    CardApplications,
    CardApplicationSend,
    NewsletterRoute,
    PatronSystemRoute
  }

  alias StatifierExamples.FormPost.CardApplications.Writer
  alias StatifierExamples.Repo

  @values ["Rowan Pell", "rowan.pell@example.com", "555-0142", "7 Orchard Row"]

  defp store!(overrides \\ %{}, scope \\ "riverbend") do
    form =
      Map.merge(
        %{
          "name" => "Rowan Pell",
          "email" => "rowan.pell@example.com",
          "phone" => "555-0142",
          "street_address" => "7 Orchard Row",
          "wants_card" => "true",
          "wants_newsletter" => "true",
          "idempotency_key" => "form-#{System.unique_integer([:positive])}"
        },
        overrides
      )

    {:ok, %CardApplication{id: id}, :created} = CardApplications.receive_application(scope, form)
    id
  end

  defp event(data) do
    %Event{Event.external("card_application.sorted") | data: data}
  end

  defp event_for(id), do: event(%{"application_id" => id, "sort" => "both"})

  defp key(ordinal \\ 1) do
    position = %{send_id: nil, macrostep: 2, microstep: 1, round: 0, c_index: nil, owner: nil}
    {"ex_card_test", position, ordinal}
  end

  defp sends, do: Repo.all(CardApplicationSend)
  defp stored(id), do: Repo.get!(CardApplication, id)

  defp assert_unchanged(id) do
    assert %CardApplication{
             status: "received",
             external_reference: nil,
             newsletter_reference: nil
           } = stored(id)
  end

  defp refute_values(term) do
    text = inspect(term, limit: :infinity, printable_limit: :infinity)
    for value <- @values, do: refute(text =~ value, "#{value} reached #{text}")
  end

  # Sabotage: dropped the write-back from `Sends.record/5`; the stored row
  # kept status "received" and this went red at the reference match, as did
  # the newsletter and both-routes tests. Reverted from a copy.
  test "the patron route records an outbox row and writes the reference back" do
    id = store!()
    reference = "RPL-P-" <> String.pad_leading(Integer.to_string(id), 6, "0")

    assert :ok = PatronSystemRoute.deliver(%{}, event_for(id), key())

    assert [
             %CardApplicationSend{
               application_id: ^id,
               route: "patron_system",
               outside_reference: ^reference,
               idempotency_key: "ex_card_test:2:1:0:1"
             }
           ] = sends()

    assert %CardApplication{
             status: "received",
             external_reference: ^reference,
             newsletter_reference: nil
           } = stored(id)
  end

  # Sabotage: gave the newsletter route the patron prefix "RPL-P-"; this
  # went red at the outbox row's reference match. Reverted from a copy.
  test "the newsletter route records an outbox row and leaves the patron reference alone" do
    id = store!()
    reference = "RPL-N-" <> String.pad_leading(Integer.to_string(id), 6, "0")

    assert :ok = NewsletterRoute.deliver(%{}, event_for(id), key())

    assert [
             %CardApplicationSend{
               application_id: ^id,
               route: "newsletter",
               outside_reference: ^reference
             }
           ] = sends()

    assert %CardApplication{
             status: "received",
             external_reference: nil,
             newsletter_reference: ^reference
           } = stored(id)
  end

  # Sabotage: made the writer put the newsletter reference in
  # `external_reference`; this went red at the stored row's match.
  # Reverted from a copy.
  test "both routes on one application keep both references" do
    id = store!()

    assert :ok = PatronSystemRoute.deliver(%{}, event_for(id), key(1))
    assert :ok = NewsletterRoute.deliver(%{}, event_for(id), key(2))

    assert %CardApplication{
             status: "sent",
             external_reference: "RPL-P-" <> _patron,
             newsletter_reference: "RPL-N-" <> _subscription
           } = stored(id)

    assert [{^id, "patron_system"}, {^id, "newsletter"}] =
             sends()
             |> Enum.map(&{&1.application_id, &1.route})
             |> Enum.sort_by(&elem(&1, 1), :desc)
  end

  # Sabotage: made the writer mark `sent` on the first route's reference
  # again; this went red at the "received" match after one route, as did
  # the single-route tests above. Dropped the newsletter write's
  # `updated_at` -> red at the stamp comparison. Reverted from a copy.
  test "an application that asked for both routes is sent only when both have answered" do
    id = store!()

    assert :ok = PatronSystemRoute.deliver(%{}, event_for(id), key(1))
    assert %CardApplication{status: "received"} = stored(id)

    # Backdate the stamp: the completing hand-off must move it.
    old = ~U[2026-01-01 00:00:00.000000Z]

    {1, _} =
      Repo.update_all(from(a in CardApplication, where: a.id == ^id), set: [updated_at: old])

    assert :ok = NewsletterRoute.deliver(%{}, event_for(id), key(2))
    assert %CardApplication{status: "sent", updated_at: stamp} = stored(id)
    assert DateTime.compare(stamp, old) == :gt
  end

  # Sabotage: required both references whatever the application asked for;
  # this went red at the "sent" match. Reverted from a copy.
  test "an application that asked for one route is sent when that route has answered" do
    card_only = store!(%{"wants_newsletter" => "false"})
    news_only = store!(%{"wants_card" => "false"})

    assert :ok = PatronSystemRoute.deliver(%{}, event_for(card_only), key(1))
    assert %CardApplication{status: "sent"} = stored(card_only)

    assert :ok = NewsletterRoute.deliver(%{}, event_for(news_only), key(2))
    assert %CardApplication{status: "sent"} = stored(news_only)
  end

  # Sabotage: made the outbox key always unique in `Sends.record/5`; the
  # second delivery wrote a second row and this went red at the one-row
  # match. Reverted from a copy.
  test "a redriven delivery answers ok and writes one outbox row" do
    id = store!()

    assert :ok = PatronSystemRoute.deliver(%{}, event_for(id), key())
    assert :ok = PatronSystemRoute.deliver(%{}, event_for(id), key())

    assert [%CardApplicationSend{application_id: ^id, route: "patron_system"}] = sends()
  end

  # Sabotage: made `Sends.record/5` write the reference back on a redrive
  # too (the nil-id branch called the writer); the planted reference and
  # stamp were overwritten and this went red at the stored row's match.
  # Reverted from a copy.
  test "a redriven delivery writes nothing back to the application" do
    id = store!()

    for route <- [PatronSystemRoute, NewsletterRoute] do
      assert :ok = route.deliver(%{}, event_for(id), key())
    end

    # Plant values no route writes, so any write-back on the redrive shows.
    stamp = ~U[2026-01-02 03:04:05.000000Z]

    {1, _} =
      Repo.update_all(
        from(a in CardApplication, where: a.id == ^id),
        set: [
          status: "received",
          external_reference: "planted-patron",
          newsletter_reference: "planted-newsletter",
          updated_at: stamp
        ]
      )

    for route <- [PatronSystemRoute, NewsletterRoute] do
      assert :ok = route.deliver(%{}, event_for(id), key())
    end

    assert %CardApplication{
             status: "received",
             external_reference: "planted-patron",
             newsletter_reference: "planted-newsletter",
             updated_at: ^stamp
           } = stored(id)

    assert [_patron, _newsletter] = sends()
  end

  # Sabotage: made `Sends.record/5` write every outbox row under
  # "patron_system"; the newsletter send hit the unique index and wrote
  # nothing, and this went red at the two-row match. Reverted from a copy.
  test "the same key on the other route is a different send" do
    id = store!()

    assert :ok = PatronSystemRoute.deliver(%{}, event_for(id), key())
    assert :ok = NewsletterRoute.deliver(%{}, event_for(id), key())

    assert [_patron, _newsletter] = sends()
  end

  # Sabotage: made `Sends.application_id/1` name the data's values instead
  # of its keys; this went red at the first refusal match. Reverted from a
  # copy.
  test "an event with no application id is refused with its keys" do
    id = store!()

    for route <- [PatronSystemRoute, NewsletterRoute] do
      assert {:error, {:no_application_id, ["sort"]}} =
               route.deliver(%{}, event(%{"sort" => "both"}), key())

      assert {:error, {:no_application_id, []}} =
               route.deliver(%{}, Event.external("card_application.sorted"), key())

      assert {:error, {:no_application_id, ["application_id"]}} =
               route.deliver(%{}, event(%{"application_id" => "12"}), key())
    end

    assert [] = sends()
    assert_unchanged(id)
  end

  # Sabotage: made the newsletter route answer the reader's bare
  # `:not_found` instead of `{:application_not_found, id}`; this went red
  # at the newsletter refusal match. Reverted from a copy.
  test "an id that names no application is refused" do
    id = store!()
    missing = id + 1000

    assert {:error, {:application_not_found, ^missing}} =
             PatronSystemRoute.deliver(%{}, event_for(missing), key())

    assert {:error, {:application_not_found, ^missing}} =
             NewsletterRoute.deliver(%{}, event_for(missing), key())

    assert [] = sends()
    assert_unchanged(id)
  end

  # Sabotage: made the patron route answer the reader's bare `:not_found`
  # instead of `{:application_not_found, id}`; this went red at the first
  # match, as did the missing-id test. Reverted from a copy.
  test "an application stored by another library system is not found" do
    other = store!(%{}, "eastbank")

    assert {:error, {:application_not_found, ^other}} =
             PatronSystemRoute.deliver(%{}, event_for(other), key())

    assert {:error, {:application_not_found, ^other}} =
             NewsletterRoute.deliver(%{}, event_for(other), key())

    assert [] = sends()
    assert_unchanged(other)
  end

  # Sabotage: skipped the `wants_card` check in the patron route; the
  # application was handed on and this went red at the refusal match.
  # Reverted from a copy.
  test "the patron route refuses an application that did not ask for a card" do
    id = store!(%{"wants_card" => "false"})

    assert {:error, {:card_not_requested, ^id}} =
             PatronSystemRoute.deliver(%{}, event_for(id), key())

    assert [] = sends()
    assert_unchanged(id)
  end

  # Sabotage: skipped the `wants_newsletter` check in the newsletter route;
  # the application was handed on and this went red at the refusal match.
  # Reverted from a copy.
  test "the newsletter route refuses an application that did not ask for the newsletter" do
    id = store!(%{"wants_newsletter" => "false"})

    assert {:error, {:newsletter_not_requested, ^id}} =
             NewsletterRoute.deliver(%{}, event_for(id), key())

    assert [] = sends()
    assert_unchanged(id)
  end

  # Sabotage: put the street address into the patron route's refusal
  # reason; this went red naming the street address in the refusals.
  # Reverted from a copy.
  test "no posted value reaches an outbox row or a refusal" do
    id = store!()
    no_card = store!(%{"wants_card" => "false"})
    no_news = store!(%{"wants_newsletter" => "false"})

    assert :ok = PatronSystemRoute.deliver(%{}, event_for(id), key(1))
    assert :ok = NewsletterRoute.deliver(%{}, event_for(id), key(2))
    refute_values(sends())

    refusals = [
      PatronSystemRoute.deliver(%{}, event(%{"sort" => "both"}), key(3)),
      PatronSystemRoute.deliver(%{}, event_for(id + 1000), key(4)),
      PatronSystemRoute.deliver(%{}, event_for(no_card), key(5)),
      NewsletterRoute.deliver(%{}, event_for(no_news), key(6))
    ]

    assert [{:error, _}, {:error, _}, {:error, _}, {:error, _}] = refusals
    refute_values(refusals)
  end

  # Sabotage: dropped the library system condition from the writer's query;
  # the eastbank write succeeded and this went red at the first match.
  # Reverted from a copy.
  test "the writer under another library system is not found and changes nothing" do
    id = store!()

    assert {:error, :not_found} =
             Writer.record_reference("eastbank", id, "patron_system", "RPL-P-X")

    assert {:error, :not_found} =
             Writer.record_reference("riverbend", id + 1000, "newsletter", "RPL-N-X")

    assert_unchanged(id)
  end
end
