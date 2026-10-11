defmodule StatifierExamples.RouterKey do
  @moduledoc """
  The one spelling of the router's idempotency key as a string, which both
  recipes' routes store: the routed recipe's
  `StatifierExamples.RoutedWorkflow.DoorstepRoute` as its job's uniqueness
  key, and the card application form's
  `StatifierExamples.FormPost.PatronSystemRoute` and
  `StatifierExamples.FormPost.NewsletterRoute` as their outbox rows' key.
  """

  @doc """
  The router's key as one string: the scope half, where in the step the
  hand-off sat (the macrostep, the microstep and the round), and the
  ordinal, which the completion hook never carries and which is spelled
  `-` when absent.

      iex> position = %{send_id: nil, macrostep: 2, microstep: 1, round: 0, c_index: nil, owner: nil}
      iex> StatifierExamples.RouterKey.join({"ex_parcel_1", position, 3})
      "ex_parcel_1:2:1:0:3"
      iex> StatifierExamples.RouterKey.join({"ex_parcel_1", position, nil})
      "ex_parcel_1:2:1:0:-"
  """
  @spec join(StatifierRouter.Route.idempotency_key()) :: String.t()
  def join({scope, position, ordinal}) do
    Enum.join(
      [scope, position.macrostep, position.microstep, position.round, ordinal || "-"],
      ":"
    )
  end
end
