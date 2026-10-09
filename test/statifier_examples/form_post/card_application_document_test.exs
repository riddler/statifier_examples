defmodule StatifierExamples.FormPost.CardApplicationDocumentTest do
  @moduledoc """
  The card application's chart, `priv/form_post/card_application.json`:
  published through this app's publish step against a router
  configuration that registers the form's two routes, compiled, described,
  and run path by path with each step's answer handed back as the host
  hands it.

  The document holds the application's id and three words in its
  datamodel and nothing the visitor typed. It screens the application
  inside a bound (the flow goes on as `unscreened` at the bound), finishes
  the execution through a handler that finishes as `abandoned` when the
  screen answers `screened_out`, sorts the application with one word, and
  runs a card lane and a newsletter lane, each guarded by that word. The
  card lane checks the service area inside its own bound (the flow goes
  on as `check_at_desk` at the bound), and each lane ends with a typed
  send to its route carrying the id and the words.

  A pure test: nothing here touches the repo, Oban or the router's tables.
  """

  use ExUnit.Case, async: true

  alias Statifier.Event
  alias Statifier.Send.Types
  alias StatifierBlocks.{Compiled, Compiler, Decode, Describe, Document}
  alias StatifierExamples.{Charts, Publish}
  alias StatifierExamples.FormPost.{NewsletterRoute, PatronSystemRoute}
  alias StatifierRouter.{Config, SendHandler}

  @path "priv/form_post/card_application.json"
  @document_id "bdoc_card_application"
  @event "application.received"

  # The router's own send type, the one this host registers.
  @send_type "myapp:route"

  @application_id 4107

  defp document do
    {:ok, document} = @path |> File.read!() |> Decode.decode()
    document
  end

  defp router_config(event \\ @event) do
    {:ok, config} =
      Config.new(
        repo: StatifierExamples.Repo,
        delivery: PatronSystemRoute,
        send_type: @send_type,
        route_adapters: %{
          PatronSystemRoute.route_name() => {PatronSystemRoute, %{}},
          NewsletterRoute.route_name() => {NewsletterRoute, %{}}
        },
        bindings: [
          %{
            id: "card_applications",
            source: "card_application_form",
            match: "true",
            key: "event.application_id",
            document: @document_id,
            event: event,
            data: ["application_id"]
          }
        ]
      )

    config
  end

  defp host(config) do
    accepts = document().accepts

    %{
      palette: Charts.palette(),
      datamodel: nil,
      send_types: %{@send_type => SendHandler},
      router_config: config,
      accepts_lookup: fn
        @document_id -> {:ok, accepts}
        _other -> {:error, :not_published}
      end,
      document_resolver: fn _document -> {:error, :not_published} end
    }
  end

  defp compiled_scxml do
    {:ok, %Compiled{scxml: scxml, warnings: []}} =
      Compiler.compile(document(), Charts.palette(), terminate: true)

    scxml
  end

  describe "publishing" do
    # Sabotage: in the fixture, the newsletter send's `target` set to
    # "newsletters"; this went red: the publish was refused. Restored from
    # a copy.
    test "every publish-time check passes, with the one accepted event and no warning" do
      assert {:ok, %Compiled{}, [@event], []} = Publish.check(document(), host(router_config()))
    end

    # Sabotage: dropped the binding findings from `contracts_stage/3` in
    # `StatifierExamples.Publish`; this went red, the document published.
    # Restored from a copy.
    test "a binding naming an event the document does not accept is refused" do
      assert {:refused, %{stage: :contracts, findings: [finding]}} =
               Publish.check(document(), host(router_config("application.withdrawn")))

      assert %{anchor: {:binding, "card_applications"}} = finding
    end

    # Sabotage: in the fixture, a fifth datamodel entry `wants_card` added;
    # this went red on the list. Restored from a copy.
    test "the datamodel holds the application's id and the three words, nothing else" do
      %Document{datamodel: datamodel} = document()

      assert Enum.map(datamodel, &{&1.id, &1.expr}) == [
               {"application_id", nil},
               {"screen", ~s("unscreened")},
               {"sort", ~s("unsorted")},
               {"area", ~s("check_at_desk")}
             ]
    end
  end

  describe "the compiled chart" do
    # Sabotage: in the fixture, the screened-out handler's `finish_as`
    # removed; this went red on the handler's abandoned final. Restored
    # from a copy.
    test "carries the capture, both bounds, the abandoned finish and the guarded sends" do
      scxml = compiled_scxml()

      for line <- [
            # The creating event's id, captured into the datamodel.
            ~s(<transition event="application.received" target="s_blk_ca_received__o_done">) <>
              ~s(<if cond="_event.data.application_id !== undefined">) <>
              ~s(<assign expr="_event.data.application_id" location="application_id"/></if>),
            # The screen, bounded: the deadline armed with the group, the
            # step handed the id, and the abandon at the bound.
            ~s(<send delay="5s" event="deadline.screen" id="s_blk_ca_screen_timer__send"/>),
            ~s(<invoke type="myapp:screen_application">) <>
              ~s(<param expr="application_id" name="application_id"/></invoke>) <>
              ~s(<transition event="done.invoke" target="s_blk_ca_screen_call__o_done">) <>
              ~s(<assign expr="_event.data" location="screen"/></transition>),
            ~s(<transition event="deadline.screen" target="s_blk_ca_screen_bound__o_done">) <>
              ~s(<raise event="statifier_blocks.interrupt.abandon.s_blk_ca_screen"/></transition>),
            ~s(<onexit><cancel sendid="s_blk_ca_screen_timer__send"/></onexit>),
            # A screened-out application finishes through the handler that
            # finishes as abandoned.
            ~s(<transition cond="screen == &quot;screened_out&quot;" target="s_blk_ca_withdraw"/>),
            ~s(<onentry><raise event="application.screened_out"/></onentry>),
            ~s(<transition event="application.screened_out" target="s_blk_ca_screened_out__o_abandoned">) <>
              ~s(<raise event="statifier_blocks.interrupt.abandon.s_blk_ca_application"/></transition>),
            ~s(<final id="s_blk_ca_screened_out__o_abandoned"><onentry>) <>
              ~s(<raise event="done.outcome.s_blk_ca_screened_out.abandoned"/></onentry></final>),
            # The sort, and the two lanes its word guards.
            ~s(<invoke type="myapp:sort_application">) <>
              ~s(<param expr="application_id" name="application_id"/></invoke>),
            ~s(<transition cond="sort in [&quot;card&quot;, &quot;both&quot;]" target="s_blk_ca_area"/>) <>
              ~s(<transition target="s_blk_ca_if_card__o_done"/>),
            ~s(<transition cond="sort in [&quot;newsletter&quot;, &quot;both&quot;]" target="s_blk_ca_send_newsletter"/>) <>
              ~s(<transition target="s_blk_ca_if_newsletter__o_done"/>),
            # The area check, bounded inside the card lane.
            ~s(<send delay="5s" event="deadline.area" id="s_blk_ca_area_timer__send"/>),
            ~s(<invoke type="myapp:check_service_area">),
            ~s(<transition event="deadline.area" target="s_blk_ca_area_bound__o_done">) <>
              ~s(<raise event="statifier_blocks.interrupt.abandon.s_blk_ca_area"/></transition>),
            # Each lane's typed send, carrying the id and the words.
            ~s(<send event="card_application.sorted" target="patron_system" type="myapp:route">) <>
              ~s(<param expr="application_id" name="application_id"/>) <>
              ~s(<param expr="screen" name="screen"/><param expr="sort" name="sort"/>) <>
              ~s(<param expr="area" name="area"/></send>),
            ~s(<send event="card_application.sorted" target="newsletter" type="myapp:route">) <>
              ~s(<param expr="application_id" name="application_id"/>) <>
              ~s(<param expr="screen" name="screen"/><param expr="sort" name="sort"/></send>)
          ] do
        assert scxml =~ line
      end
    end
  end

  describe "what Describe shows" do
    # Sabotage: in the fixture, the card lane's condition set to
    # `sort == "card"`; this went red on the card lane's sentence. Restored
    # from a copy.
    test "names the capture, each bound, each guard and each send" do
      lines = Describe.render(Describe.outline(document(), Charts.palette(), []), [])

      for line <- [
            "Wait 1h",
            "On application.received, When application.received, abandon abandons the group",
            "In 5 seconds, send deadline.screen",
            "On deadline.screen, When deadline.screen, abandon abandons the group",
            "In 5 seconds, deadline.screen reaches When deadline.screen, abandon",
            ~s(The branch: when screen == "screened_out", Raise),
            "On application.screened_out, When application.screened_out, abandon abandons the group",
            ~s[After Decide: When "screened_out", otherwise (done), Invoke],
            "After Invoke (done, error), Run 2 lanes at the same time",
            "Run 2 lanes at the same time (all of)",
            ~s(The branch: when sort in ["card", "both"], Run interruptible steps),
            "After Run interruptible steps (done), Hand to the patron system",
            "On deadline.area, When deadline.area, abandon abandons the group",
            "In 5 seconds, deadline.area reaches When deadline.area, abandon",
            ~s(The branch: when sort in ["newsletter", "both"], Hand to the newsletter list)
          ] do
        assert line in lines, "#{inspect(line)} is not in #{inspect(lines)}"
      end
    end
  end

  describe "the chart, run" do
    setup do
      {:ok, machine} = Statifier.compile(compiled_scxml())
      %{machine: machine}
    end

    # Sabotage: in the fixture, the newsletter send's payload gained
    # "area"; this went red on the newsletter send's data. Restored from a
    # copy.
    test "both: the screen and the area answer, and each route gets the id and the words",
         ctx do
      {state, invoke} = received(ctx.machine)
      assert invoke.type == "myapp:screen_application"
      assert invoke.params == %{"application_id" => @application_id}

      {state, effects} = answer(state, invoke, "ok")
      assert cancelled(effects) == ["s_blk_ca_screen_timer__send"]
      [sort] = invokes(effects)
      assert sort.type == "myapp:sort_application"
      assert sort.params == %{"application_id" => @application_id}

      # The newsletter lane has nothing to wait for, so its send goes out
      # when the sort answers, before the area check is asked.
      {state, effects} = answer(state, sort, "both")

      assert sends(effects) == [
               {"newsletter", "card_application.sorted",
                %{"application_id" => @application_id, "screen" => "ok", "sort" => "both"}}
             ]

      [area] = invokes(effects)
      assert area.type == "myapp:check_service_area"

      {state, effects} = answer(state, area, "inside")

      assert sends(effects) == [
               {"patron_system", "card_application.sorted",
                %{
                  "application_id" => @application_id,
                  "screen" => "ok",
                  "sort" => "both",
                  "area" => "inside"
                }}
             ]

      assert finished?(state)
    end

    # Sabotage: in the fixture, the screen's datamodel default removed;
    # this went red on the patron send's `"screen"`. Restored from a copy.
    test "a card only, with both bounds passing: the flow goes on as unscreened and check_at_desk",
         ctx do
      {state, invoke} = received(ctx.machine)

      {:ok, state, effects} = Statifier.send_event(state, "deadline.screen")
      assert cancelled(effects) == ["s_blk_ca_screen_timer__send"]
      assert [%{type: "myapp:sort_application"} = sort] = invokes(effects)
      refute invoke.invoke_id == sort.invoke_id

      {state, effects} = answer(state, sort, "card")
      assert [%{type: "myapp:check_service_area"}] = invokes(effects)

      {:ok, state, effects} = Statifier.send_event(state, "deadline.area")

      assert sends(effects) == [
               {"patron_system", "card_application.sorted",
                %{
                  "application_id" => @application_id,
                  "screen" => "unscreened",
                  "sort" => "card",
                  "area" => "check_at_desk"
                }}
             ]

      assert finished?(state)
    end

    # Sabotage: in the fixture, the newsletter lane's condition set to
    # `sort in ["card", "both"]`; this went red on the sends. Restored
    # from a copy.
    test "the newsletter only: one send to the newsletter list and no area check", ctx do
      {state, invoke} = received(ctx.machine)
      {state, effects} = answer(state, invoke, "ok")
      [sort] = invokes(effects)

      {state, effects} = answer(state, sort, "newsletter")

      assert invokes(effects) == []

      assert sends(effects) == [
               {"newsletter", "card_application.sorted",
                %{"application_id" => @application_id, "screen" => "ok", "sort" => "newsletter"}}
             ]

      assert finished?(state)
    end

    # Sabotage: in the fixture, the card lane's condition set to `true`;
    # this went red: the card lane checked the area. Restored from a copy.
    test "neither: no lane runs, nothing is sent, and the execution finishes", ctx do
      {state, invoke} = received(ctx.machine)
      {state, effects} = answer(state, invoke, "ok")
      [sort] = invokes(effects)

      {state, effects} = answer(state, sort, "neither")

      assert invokes(effects) == []
      assert sends(effects) == []
      assert finished?(state)
    end

    # Sabotage: in the fixture, the branch's raise renamed to
    # `application.withdrawn`; this went red: the sort was invoked.
    # Restored from a copy.
    test "screened out: the execution finishes as abandoned, with no sort and no send", ctx do
      {state, invoke} = received(ctx.machine, trace: true)

      {:ok, state, effects} =
        Statifier.send_event(
          state,
          Event.external("done.invoke." <> invoke.invoke_id,
            data: "screened_out",
            invokeid: invoke.invoke_id
          )
        )

      assert invokes(effects) == []
      assert sends(effects) == []
      assert finished?(state)
      assert "done.outcome.s_blk_ca_screened_out.abandoned" in dequeued(effects)
    end
  end

  # The execution, created and handed the event that opened it, as the
  # router creates and delivers: answers the state and the screen's invoke.
  defp received(machine, opts \\ []) do
    {state, _effects} =
      Statifier.initialize(
        machine,
        [send_types: Types.from_send_types(%{@send_type => SendHandler})] ++ opts
      )

    {:ok, state, effects} =
      Statifier.send_event(
        state,
        Event.external(@event, data: %{"application_id" => @application_id})
      )

    [invoke] = invokes(effects)
    {state, invoke}
  end

  # The step's answer, handed back as the invoke's completion.
  defp answer(state, invoke, word) do
    {:ok, state, effects} =
      Statifier.send_event(
        state,
        Event.external("done.invoke." <> invoke.invoke_id, data: word, invokeid: invoke.invoke_id)
      )

    {state, effects}
  end

  defp invokes(effects), do: for({:invoke, invoke} <- effects, do: invoke)

  defp sends(effects),
    do: for({:send, send} <- effects, do: {send.target, send.event, send.data})

  defp cancelled(effects), do: for({:cancel, cancel} <- effects, do: cancel.send_id)

  defp finished?(state), do: match?({:error, :not_running}, Statifier.send_event(state, "noop"))

  # The names of the events the step processed, internal ones included:
  # the trace effects a position created with `trace: true` emits.
  defp dequeued(effects) do
    for {_tag, %Statifier.Effect.Trace.EventDequeued{event: event}} <- effects, do: event.name
  end
end
