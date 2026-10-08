defmodule UpgradeHost.Registrations.FormPost do
  @moduledoc """
  The job that routes one accepted registration post, after the host has
  answered the patron. Its arguments are ids only: the branch and the
  patron.

  It hands the post to `StatifierRouter.Webhook.handle/3` and reads the
  answer as a provider would read the status: `200` is settled, whatever
  the outcome (a duplicate included), and `500` is an attempt that did not
  settle, which Oban retries. A post that created the registration's
  execution has that execution's id kept on the patron's row, in the same
  transaction as the delivery.
  """

  use Oban.Worker, queue: :registrations

  alias StatifierRouter.Webhook
  alias UpgradeHost.{Registrations, Repo}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"branch_id" => branch_id, "patron_id" => patron_id}}) do
    Repo.transaction(fn ->
      answer = Registrations.route(branch_id, patron_id)

      case Webhook.status(answer) do
        200 ->
          {:ok, outcomes} = answer

          for {:created_and_delivered, _binding_id, execution_id} <- outcomes,
              do: :ok = Registrations.record_execution(patron_id, execution_id)

          outcomes

        500 ->
          {:error, reason} = answer
          Repo.rollback(reason)
      end
    end)
  end
end
