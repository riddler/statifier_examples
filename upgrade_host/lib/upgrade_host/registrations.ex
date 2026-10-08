defmodule UpgradeHost.Registrations do
  @moduledoc """
  Patron registration, as a durable execution a form post reaches through
  `statifier_router`'s webhook front: the host's first router binding.

  A patron fills in the registration form at a branch. The host answers
  the post itself (`submit/2`): it keeps the form's personal fields in its
  own `patrons` table, under an id it owns, and enqueues a job carrying
  ids only. The job (`UpgradeHost.Registrations.FormPost`) hands the post
  to `StatifierRouter.Webhook.handle/3`, and the one binding routes it to
  the patron's registration execution, creating it. The registration
  waits for the patron to confirm (`confirm/2`) and ends there.

  What crosses into the family is the patron's id and the branch, never
  the form's fields: the message's `provider_id` and `raw_body` are both
  the patron id, its data is `%{"patron_id" => id}`, and the binding
  projects only that field, so the router's rows and the execution's
  datamodel carry the id alone.

  The address `(branch, "patron_registration", patron id)` names one
  execution at a time. `reap/1` is the host's scheduled sweep: it removes
  the expired dedupe rows and, once an ended registration's horizon has
  passed, its address row, so the patron's next registration opens a new
  execution.

  Every delivery the router drives runs inside the host's tenancy context
  (`UpgradeHost.Tenancy`), set by `UpgradeHost.Registrations.Seams`'s
  `around_delivery/3`; the create and the step it stands in for read it.
  """

  import Ecto.Query, only: [from: 2]

  alias Statifier.{Event, Machine}
  alias StatifierPersistence.{Execution, Storage}
  alias StatifierRouter.{Addresses, Binding, Config, Dedupe}
  alias UpgradeHost.Registrations.{FormPost, Patron, Seams}
  alias UpgradeHost.{Repo, Tenancy}

  @document "patron_registration"
  @source "patron_registration_form"
  @binding_id "registration_form_to_patron"

  # A resubmitted form is the same message for an hour; the address row of
  # an ended registration is kept as long, so a late resubmission is still
  # answered as a duplicate rather than opening a second execution.
  @horizon_ms 3_600_000

  @scxml """
  <scxml xmlns="http://www.w3.org/2005/07/scxml" version="1.0" initial="received">
    <datamodel>
      <data id="patron_id"/>
    </datamodel>
    <state id="received">
      <transition event="registration.submitted" target="awaiting_confirmation">
        <assign location="patron_id" expr="_event.data.patron_id"/>
      </transition>
    </state>
    <state id="awaiting_confirmation">
      <transition event="registration.confirmed" target="registered"/>
    </state>
    <final id="registered"/>
  </scxml>
  """

  @doc "The document every registration execution belongs to."
  @spec document() :: String.t()
  def document, do: @document

  @doc "The source the registration form posts under."
  @spec source() :: String.t()
  def source, do: @source

  @doc "The chart's SCXML source."
  @spec scxml() :: String.t()
  def scxml, do: @scxml

  @doc "The registration chart, compiled once per node and kept."
  @spec machine() :: Machine.t()
  def machine do
    case :persistent_term.get({__MODULE__, :machine}, nil) do
      nil ->
        {:ok, machine} = Statifier.compile(@scxml, chart_name: @document)
        :persistent_term.put({__MODULE__, :machine}, machine)
        machine

      machine ->
        machine
    end
  end

  @doc """
  The one binding: a post from the registration form addresses the
  patron's registration, keyed by the patron id, and is delivered as
  `registration.submitted` carrying that id alone.
  """
  @spec bindings() :: [Binding.t()]
  def bindings do
    {:ok, binding} =
      Binding.new(
        id: @binding_id,
        source: @source,
        match: "event.patron_id != ''",
        key: "event.patron_id",
        document: @document,
        event: "registration.submitted",
        data: ["patron_id"],
        dedupe: %{by: :message_id, horizon_ms: @horizon_ms}
      )

    [binding]
  end

  @doc """
  The router's configuration: the host's repo and the store its
  executions are kept in, the router's tables under the host's `routing_`
  prefix, the binding, and the host's engine in every seam a delivery
  calls.
  """
  @spec router_config() :: Config.t()
  def router_config do
    {:ok, config} =
      Config.new(
        repo: Repo,
        store: store(),
        table_prefix: "routing_",
        bindings: bindings(),
        executor: Seams,
        resolver: Seams,
        chart_resolver: &Seams.chart/1,
        on_create: Seams,
        on_step: Seams,
        around_delivery: Seams
      )

    config
  end

  @doc "The store every registration is kept in, over the host's repo."
  @spec store() :: Storage.t()
  def store do
    {:ok, store} =
      Storage.new(StatifierPersistence.Storage.Ecto, persistence: UpgradeHost.Persistence)

    store
  end

  @doc """
  The host's answer to a posted registration form: keeps the patron's
  fields in its own table (the same patron when the branch already holds
  that email), enqueues the job that routes the post, and answers the
  patron's id. Nothing has been routed yet when it answers.
  """
  @spec submit(String.t(), %{required(String.t()) => String.t()}) ::
          {:ok, String.t()} | {:error, term()}
  def submit(branch_id, %{"name" => name, "email" => email}) do
    Repo.transaction(fn ->
      patron = patron!(branch_id, name, email)

      case Oban.insert(
             UpgradeHost.Oban,
             FormPost.new(%{"branch_id" => branch_id, "patron_id" => patron.id})
           ) do
        {:ok, _job} -> patron.id
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp patron!(branch_id, name, email) do
    case Repo.get_by(Patron, branch_id: branch_id, email: email) do
      nil ->
        Repo.insert!(%Patron{
          id: UXID.generate!(prefix: "patron"),
          branch_id: branch_id,
          name: name,
          email: email
        })

      patron ->
        patron
    end
  end

  @doc """
  Routes one registration post through the webhook front: the host has
  already accepted it, so there is nothing left to verify. The message id
  is the patron id (`provider_id`), and the raw body is that id too.
  """
  @spec route(String.t(), String.t()) :: StatifierRouter.Webhook.answer()
  def route(branch_id, patron_id) do
    StatifierRouter.Webhook.handle(router_config(), %{
      scope: branch_id,
      source: @source,
      raw_body: patron_id,
      provider_id: patron_id,
      data: %{"patron_id" => patron_id}
    })
  end

  @doc """
  Keeps the id of the execution a routed post created on the patron's
  row, the one place the host joins its patron to the registration.
  """
  @spec record_execution(String.t(), String.t()) :: :ok
  def record_execution(patron_id, execution_id) do
    {1, _} =
      Repo.update_all(from(p in Patron, where: p.id == ^patron_id),
        set: [registration_execution_id: execution_id, updated_at: DateTime.utc_now()]
      )

    :ok
  end

  @doc """
  The patron confirms: the registration execution the patron's row names
  is stepped with `registration.confirmed`, inside the branch's tenancy
  context, and ends.
  """
  @spec confirm(String.t(), String.t()) ::
          {:ok, Execution.t(), Statifier.MachineState.t()}
          | {:discarded, Execution.t()}
          | {:error, term()}
  def confirm(branch_id, patron_id) do
    case Repo.get_by(Patron, id: patron_id, branch_id: branch_id) do
      %Patron{registration_execution_id: execution_id} when is_binary(execution_id) ->
        Tenancy.run(branch_id, fn ->
          Seams.step(
            store(),
            execution_id,
            machine(),
            Event.external("registration.confirmed"),
            executor: Seams
          )
        end)

      _none ->
        {:error, :no_registration}
    end
  end

  @doc """
  The host's scheduled sweep at `now`: removes the dedupe rows expired by
  then, and the address rows of registrations that ended at least a
  horizon before it.
  """
  @spec reap(DateTime.t()) ::
          {:ok, %{dedupe: non_neg_integer(), addresses: Addresses.result()}} | {:error, term()}
  def reap(now) do
    config = router_config()
    {:ok, dedupe} = Dedupe.reap(config, now)

    with {:ok, addresses} <- Addresses.reap(config, config.bindings, now: now) do
      {:ok, %{dedupe: dedupe, addresses: addresses}}
    end
  end
end
