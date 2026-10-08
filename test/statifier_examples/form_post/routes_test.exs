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
             status: "sent",
             external_reference: ^reference,
             newsletter_reference: nil
           } = stored(id)
  end

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
             status: "sent",
             external_reference: nil,
             newsletter_reference: ^reference
           } = stored(id)
  end

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

  # Sabotage: made the outbox key always unique in `Sends.record/5`; the
  # second delivery wrote a second row and this went red at the one-row
  # match. Reverted from a copy.
  test "a redriven delivery answers ok and writes one outbox row" do
    id = store!()

    assert :ok = PatronSystemRoute.deliver(%{}, event_for(id), key())
    assert :ok = PatronSystemRoute.deliver(%{}, event_for(id), key())

    assert [%CardApplicationSend{application_id: ^id, route: "patron_system"}] = sends()
  end

  test "the same key on the other route is a different send" do
    id = store!()

    assert :ok = PatronSystemRoute.deliver(%{}, event_for(id), key())
    assert :ok = NewsletterRoute.deliver(%{}, event_for(id), key())

    assert [_patron, _newsletter] = sends()
  end

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
