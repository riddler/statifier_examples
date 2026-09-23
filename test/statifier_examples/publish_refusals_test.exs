defmodule StatifierExamples.PublishRefusalsTest do
  @moduledoc """
  The refusal suite: six charts `StatifierExamples.Publish.check/2` refuses,
  each beside what the engine does when the same chart runs anyway.

  The cases are JSON files under `test/fixtures/publish_refusals/`, one per
  case, in a shape of this app's own that the `README.md` beside them
  documents. Each case carries the document, the host state it is judged
  against, the stage that refuses it and what running it shows. This module
  reads each case twice:

    * once through `Publish.check/2`, asserting the stage and the finding
      the case names; and
    * once on the engine, starting the same chart - compiled from the same
      document against the same palette - in a `Statifier.Session` with the
      same send types, the same routes, the same bindings and the same
      published children, and asserting what the case records it does.

  Where the engine refuses the chart itself, that refusal is asserted. Where
  it refuses nothing - an event its chart never listens for, a child
  outcome its parent never routes on, a capture of a payload key the event
  does not carry - today's behaviour is asserted instead, so a later
  release that adds a refusal there turns the case red and the case is
  updated on purpose.

  ## The host pieces the tests supply

  Four small modules below stand in for what a host wires up and this app
  does not ship:

    * `NoticeRoute` - a route adapter, so the router configuration has
      registered route names;
    * `NoAddressRows` - the router configuration's repo. The router's send
      handler looks the sender up in its own address table before it
      records a refused send there, and this app carries none of the
      router's tables. No execution here is created by the router, so a
      host that did carry them would find no row for it either: the
      lookup answers `nil`, the refusal is reported and not recorded, which
      is the branch the handler documents for a sender with no address row;
    * `RouterSends` - the send processor registered under the router's send
      type. It hands every send to `StatifierRouter.SendHandler`, with the
      configuration installed in the session process that performs it, and
      when the handler answers `{:error, reason}` it reports the miss
      through `Statifier.Session.failed_send/3`. The router's handler
      documents that reporting as the host's;
    * `CaseResolver` - the in-memory subchart handler's resolver, over the
      children the cases publish.

  The typed send two of the cases need is `StatifierExamples.TypedSendStep`,
  in `test/support/`: this app's palette has no step that writes a
  `<send>` with a `type`.

  Every session here is started with `trace: true` and this process as a
  subscriber, so what the engine dequeued - the platform error events
  among them - arrives here as trace effects.
  """

  # Not async: a session registers under the application's own
  # `Statifier.Registry`, and `RouterSends` reads its configuration from
  # a persistent term this module writes per test.
  use ExUnit.Case, async: false

  alias Statifier.Effect.Trace.EventDequeued
  alias StatifierBlocks.{Compiled, Compiler, Decode, Document, Edit}
  alias StatifierExamples.{Charts, Publish, TypedSendStep}
  alias StatifierExamples.Charts.Subchart

  @cases_dir "test/fixtures/publish_refusals"

  @cases ~w(
    unregistered_send_type
    unregistered_route
    undeclared_receiver_event
    unresolvable_child
    dropped_consumed_outcome
    undeclared_payload_capture
  )

  # The send type the router's handler answers to, in every case's host.
  @router_type "myapp:sink"

  defmodule NoticeRoute do
    @moduledoc false
    @behaviour StatifierRouter.Route

    @impl true
    def deliver(_route_config, _event, _key), do: :ok
  end

  defmodule NoAddressRows do
    @moduledoc false

    # The one repo call the send handler's refusal path makes.
    def one(_query), do: nil
  end

  defmodule RouterSends do
    @moduledoc false
    @behaviour Statifier.Send.Processor

    alias StatifierRouter.SendHandler

    @impl true
    def deliver(effect, event, ctx), do: SendHandler.deliver(effect, event, ctx) |> own()

    @impl true
    def cancel(cancel, ctx), do: SendHandler.cancel(cancel, ctx) |> own()

    @impl true
    def ioprocessors_entry(type), do: SendHandler.ioprocessors_entry(type)

    # Runs in the session process, which is where the handler reads its
    # configuration from.
    @impl true
    def perform(payload, ctx) do
      SendHandler.put_config(:persistent_term.get({__MODULE__, :config}))
      answer = SendHandler.perform(payload, ctx)
      send(:persistent_term.get({__MODULE__, :observer}), {:handler_answered, answer})
      report(answer, payload)
      answer
    end

    defp report({:error, reason}, {:send, effect, _event, _key}),
      do: Statifier.Session.failed_send(self(), effect, reason: reason)

    defp report(_answer, _payload), do: :ok

    # The handler's instructions name the handler; the session must call
    # this module's `perform/2` instead, so the answer is seen here.
    defp own({:ok, instructions}),
      do:
        {:ok,
         for({:handler, _module, payload} <- instructions, do: {:handler, __MODULE__, payload})}
  end

  defmodule CaseResolver do
    @moduledoc false
    use StatifierBlocks.Runtime.Subchart

    @impl StatifierBlocks.Runtime.Subchart
    def resolve_chart(document_id, _ctx) do
      case Enum.find(StatifierExamples.PublishRefusalsTest.published(), &(&1.id == document_id)) do
        nil -> :error
        document -> {:ok, document}
      end
    end

    @impl StatifierBlocks.Runtime.Subchart
    def palette, do: StatifierExamples.Charts.palette()
  end

  setup do
    on_exit(fn ->
      :persistent_term.erase({RouterSends, :config})
      :persistent_term.erase({RouterSends, :observer})
    end)
  end

  describe "the suite" do
    # Sabotage: deleted the unresolvable_child row from the cases' README;
    # this went red naming the case. Restored from a copy.
    test "holds the six cases, and its README has one row per case naming its stage" do
      files =
        @cases_dir |> File.ls!() |> Enum.filter(&String.ends_with?(&1, ".json")) |> Enum.sort()

      assert files == Enum.sort(Enum.map(@cases, &(&1 <> ".json")))

      readme = File.read!(Path.join(@cases_dir, "README.md"))

      for name <- @cases do
        kase = load!(name)
        stage = kase.publish["stage"]

        assert readme =~ ~r/^\| `#{name}` \| `:#{stage}` \|/m,
               "the README has no row for #{name} at the #{stage} stage"
      end
    end

    # Sabotage: set the parcel case's metadata domain to a name outside the
    # three teaching domains; this went red. Restored from a copy.
    test "every case is in the library world or the parcel world" do
      for name <- @cases do
        kase = load!(name)
        assert kase.world in ["library_loan", "patron_registration", "parcel_delivery"]
        assert kase.document.metadata["domain"] == kase.world
      end
    end
  end

  describe "a send whose type no processor is registered for" do
    # Sabotage: dropped send_types_stage/2 from Publish.check/2; this went
    # red, the chart refused at the contracts stage instead. Reverted from a
    # copy.
    test "is refused at the send_types stage" do
      assert_refused("unregistered_send_type", :send_types)
    end

    # Sabotage: registered "myapp:courier" in the session's send types; this
    # went red, no error.execution dequeued. Reverted from a copy.
    test "on the engine, raises error.execution naming the type" do
      assert_engine("unregistered_send_type")
    end
  end

  describe "a send to a route the host never registered" do
    # Sabotage: dropped routes_stage/2 from Publish.check/2; this went red,
    # the chart refused at the contracts stage instead. Reverted from a copy.
    test "is refused at the routes stage" do
      assert_refused("unregistered_route", :routes)
    end

    # Sabotage: made RouterSends report nothing on {:error, _}; this went
    # red, no error.communication dequeued. Reverted from a copy.
    test "on the engine, the router's handler refuses it and the chart hears error.communication" do
      assert_engine("unregistered_route")
    end
  end

  describe "a binding that routes an event its receiver does not declare" do
    # Sabotage: dropped the undeclared_binding_events arm from
    # contracts_stage/3; this went red, the chart published. Reverted from a
    # copy.
    test "is refused at the contracts stage, on the binding" do
      assert_refused("undeclared_receiver_event", :contracts)
    end

    # Sabotage: added parcel.lost to the parcel's interrupts in memory
    # before starting it; this went red, the configuration changed. Reverted
    # from a copy.
    test "on the engine, the event is delivered and discarded without a word" do
      assert_engine("undeclared_receiver_event")
    end
  end

  describe "a child document nothing publishes" do
    # Sabotage: dropped graph_stage/2 from Publish.check/2; this went red,
    # the chart published. Reverted from a copy.
    test "is refused at the graph stage, on the block's chart field" do
      assert_refused("unresolvable_child", :graph)
    end

    # Sabotage: made CaseResolver answer the first published case child for
    # any id; this went red, a child started and nothing was raised.
    # Reverted from a copy.
    test "on the engine, the child fails to start as unknown_document" do
      assert_engine("unresolvable_child")
    end
  end

  describe "a parent routing on an outcome its child no longer declares" do
    # Sabotage: made graph_stage/2 keep only :warning findings; this went
    # red, the chart published. Reverted from a copy.
    test "is refused at the graph stage, on the block's outcomes field" do
      assert_refused("dropped_consumed_outcome", :graph)
    end

    # Sabotage: set the parent subchart's outcomes to "received\nrefused"
    # in memory before starting it; this went red, the received answer took
    # its own arm and the refused path never ran. Reverted from a copy.
    test "on the engine, the child's answer falls to the parent's unconditioned arm" do
      assert_engine("dropped_consumed_outcome")
    end
  end

  describe "a capture of a payload key the event does not declare" do
    # Sabotage: dropped findings_stage/3 from Publish.check/2; this went
    # red, the chart refused at the compile stage instead. Reverted from a
    # copy.
    test "is refused at the findings stage, on the capture" do
      assert_refused("undeclared_payload_capture", :findings)
    end

    # Sabotage: sent the event with an email key in its data; this went
    # red, the patron root written. Reverted from a copy.
    test "on the engine, the capture writes nothing and nothing is raised" do
      assert_engine("undeclared_payload_capture")
    end

    # The document is refused before it compiles, so the chart the engine
    # runs is compiled with the payload declaration dropped, which is what
    # the finding offers as one way out. This pins that the declaration
    # changes no byte of the chart: dropping it and declaring the missing
    # key compile the same SCXML.
    #
    # Sabotage: compiled the declared variant with an extra key in the
    # payload and a capture reading it; this went red. Reverted from a copy.
    test "declaring or dropping the payload compiles the same chart" do
      kase = load!("undeclared_payload_capture")
      {:ok, %Compiled{scxml: dropped}} = compile(kase, running_document(kase))
      {:ok, %Compiled{scxml: declared}} = compile(kase, declare_captured_keys(kase.document))

      assert dropped == declared
    end
  end

  # ------------------------------------------------------------------
  # The publish half
  # ------------------------------------------------------------------

  defp assert_refused(name, stage) do
    kase = load!(name)
    assert kase.publish["stage"] == Atom.to_string(stage)

    assert {:refused, %{stage: ^stage, findings: findings}} =
             Publish.check(kase.document, host(kase))

    check = kase.publish["check"]
    anchor = kase.publish["anchor"]

    assert Enum.any?(
             findings,
             &(Atom.to_string(&1.check) == check and anchor?(&1.anchor, anchor))
           ),
           "no #{check} finding anchored #{inspect(anchor)} in #{inspect(findings)}"
  end

  # A case names an anchor as a JSON list: `["scxml"]` for any element of
  # the generated chart, `["binding", id]`, or `["config", block_id, key]`.
  defp anchor?({:scxml, _location}, ["scxml"]), do: true
  defp anchor?({:binding, id}, ["binding", id]), do: true
  defp anchor?({:config, block_id, key}, ["config", block_id, key]), do: true
  defp anchor?(_anchor, _named), do: false

  # The host state a case is judged against: this app's palette, with the
  # typed send registered when the case needs it; the case's send types,
  # routes and bindings; and two lookups over the document under check and
  # the documents the case publishes.
  defp host(kase) do
    documents = [kase.document | kase.published]

    %{
      palette: palette(kase),
      datamodel: nil,
      declare: [],
      send_types: send_types(kase),
      router_config: router_config(kase),
      accepts_lookup: fn document_id ->
        case Enum.find(documents, &(&1.id == document_id)) do
          nil -> {:error, :not_published}
          document -> {:ok, document.accepts}
        end
      end,
      document_resolver: fn document_id ->
        case Enum.find(kase.published, &(&1.id == document_id)) do
          nil -> {:error, :not_published}
          document -> Subchart.child_compile(document)
        end
      end
    }
  end

  defp palette(kase) do
    if TypedSendStep.type_name() in kase.block_types,
      do: TypedSendStep.palette(),
      else: Charts.palette()
  end

  defp send_types(kase), do: Map.new(kase.send_types, &{&1, RouterSends})

  defp router_config(kase) do
    {:ok, config} =
      StatifierRouter.Config.new(
        repo: NoAddressRows,
        delivery: NoticeRoute,
        send_type: @router_type,
        route_adapters: Map.new(kase.routes, &{&1, {NoticeRoute, %{}}}),
        bindings: kase.bindings
      )

    config
  end

  # ------------------------------------------------------------------
  # The engine half
  # ------------------------------------------------------------------

  defp assert_engine(name) do
    kase = load!(name)
    expect = kase.runtime["expect"]
    pid = start!(kase)
    before = configuration(pid)

    deliver(pid, kase.runtime["deliver"])

    if answer = expect["handler_answer"] do
      assert_receive {:handler_answered, {:error, reason}}, 1_000
      assert json(reason) == answer
    end

    for raised <- expect["raised"] || [] do
      assert_dequeued(raised)
    end

    if state = expect["reached"], do: assert(state in configuration(pid))

    if expect["unchanged_configuration"], do: assert(configuration(pid) == before)

    if root = expect["unwritten"] do
      assert Statifier.Session.snapshot(pid).datamodel[root] == nil
    end

    if expect["quiet"] do
      assert [] == for(%{name: "error." <> _} = event <- dequeued(pid), do: event)
    end
  end

  # The same chart the publish half judged: the same document, compiled
  # against the same palette with the same options `Publish.check/2`'s
  # compile stage passes, then started with the case's send types and the
  # subchart handler over the case's published children.
  defp start!(kase) do
    :persistent_term.put({RouterSends, :config}, router_config(kase))
    :persistent_term.put({RouterSends, :observer}, self())

    {:ok, %Compiled{scxml: scxml}} = compile(kase, running_document(kase))
    {:ok, machine} = Statifier.compile(scxml)

    {:ok, pid} =
      Statifier.Session.start_link(machine,
        send_types: send_types(kase),
        invoke_handlers: StatifierBlocks.Runtime.Subchart.handlers(CaseResolver),
        inherit_invoke_handlers: true,
        trace: true,
        subscribers: [self()]
      )

    on_exit(fn -> if Process.alive?(pid), do: Statifier.Session.stop(pid) end)

    pid
  end

  defp compile(kase, document),
    do: Compiler.compile(document, palette(kase), datamodel: nil, declare: [])

  # A document whose compile refuses cannot run; the one case of those is
  # run with its payload declaration dropped (see the test above).
  defp running_document(%{name: "undeclared_payload_capture", document: document}) do
    update_config(document, "blk_pr_verified", &Map.delete(&1, "payload"))
  end

  defp running_document(kase), do: kase.document

  defp declare_captured_keys(document) do
    update_config(document, "blk_pr_verified", fn config ->
      Map.update!(config, "payload", &(&1 ++ [%{"name" => "email", "type" => "string"}]))
    end)
  end

  defp update_config(document, block_id, fun) do
    block = document |> Document.blocks() |> Enum.find(&(&1.id == block_id))

    {:ok, updated, _inverse} =
      Edit.apply(document, {:update_config, block_id, fun.(block.config)})

    updated
  end

  defp deliver(_pid, nil), do: :ok

  defp deliver(pid, %{"to" => "execution", "event" => event, "data" => data}),
    do: Statifier.Session.send_event(pid, Statifier.Event.external(event, data: data))

  defp deliver(pid, %{"to" => "child", "event" => event, "data" => data}) do
    assert [%{pid: child}] = Statifier.Session.invocations(pid)
    Statifier.Session.send_event(child, Statifier.Event.external(event, data: data))
  end

  defp configuration(pid), do: Statifier.Session.status(pid).configuration

  defp assert_dequeued(%{"event" => name} = raised) do
    assert_receive {:statifier, _session,
                    {:effect, {:trace, %EventDequeued{event: %{name: ^name} = event}}}},
                   1_000

    if Map.has_key?(raised, "data"), do: assert(json(event.data) == raised["data"])
    if raised["sendid"], do: assert(is_binary(event.sendid))
  end

  # Every event this session has dequeued so far. Two status calls first:
  # a send refused while the session drains its start is reported by a cast
  # the session makes to itself, which can land behind the first call but
  # never behind the second.
  defp dequeued(pid) do
    Statifier.Session.status(pid)
    Statifier.Session.status(pid)
    drain([])
  end

  defp drain(events) do
    receive do
      {:statifier, _session, {:effect, {:trace, %EventDequeued{event: event}}}} ->
        drain([event | events])
    after
      0 -> Enum.reverse(events)
    end
  end

  # An engine value as the case files spell it: a tuple is a list whose
  # atoms are strings.
  defp json(value) when is_tuple(value), do: value |> Tuple.to_list() |> Enum.map(&json/1)

  defp json(value) when is_atom(value) and value not in [nil, true, false],
    do: Atom.to_string(value)

  defp json(value) when is_map(value), do: Map.new(value, fn {k, v} -> {k, json(v)} end)
  defp json(value), do: value

  # ------------------------------------------------------------------
  # The case files
  # ------------------------------------------------------------------

  @doc false
  def published do
    Enum.flat_map(@cases, &load!(&1).published)
  end

  defp load!(name) do
    kase = @cases_dir |> Path.join(name <> ".json") |> File.read!() |> Jason.decode!()
    host = kase["host"]

    %{
      name: kase["case"],
      world: kase["world"],
      document: decode!(kase["document"]),
      block_types: host["block_types"],
      send_types: host["send_types"],
      routes: host["routes"],
      bindings: Enum.map(host["bindings"], &binding_fields/1),
      published: Enum.map(host["published"], &decode!/1),
      publish: kase["publish"],
      runtime: kase["runtime"]
    }
  end

  @binding_keys ~w(id source match key document event)

  defp binding_fields(fields),
    do: Map.new(@binding_keys, &{String.to_existing_atom(&1), fields[&1]})

  defp decode!(document) do
    {:ok, %Document{} = decoded} = document |> Jason.encode!() |> Decode.decode()
    decoded
  end
end
