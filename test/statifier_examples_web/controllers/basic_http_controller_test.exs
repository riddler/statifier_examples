defmodule StatifierExamplesWeb.BasicHTTPControllerTest do
  use StatifierExamplesWeb.ConnCase, async: false

  import ExUnit.CaptureLog

  alias StatifierExamples.{FirstWorkflow, HoldDesk, RoutedWorkflow}
  alias StatifierPersistence.{Execution, Executions, Storage}
  alias StatifierRouter.BasicHTTP

  # A patron's hold on a copy at the Riverside branch: the execution tells
  # the desk it was placed, handing it the location to answer at, and the
  # desk posts copy.shelved there through the controller.

  @scope "branch_riverside"
  @desk "https://riverside.example/holds-desk"
  @form "application/x-www-form-urlencoded"

  setup do
    {:ok, _content_hash} = HoldDesk.register()
    :ok
  end

  defp placed_hold(hold_id \\ "hold-0417") do
    assert {:ok, [{:created_and_delivered, "hold_requests", execution_id}]} =
             HoldDesk.request(@scope, %{
               "hold_id" => hold_id,
               "copy_id" => "copy-2231",
               "desk" => @desk
             })

    assert_received {:desk_post, @desk, headers, body}
    {execution_id, headers, URI.decode_query(body)}
  end

  defp token(location), do: String.replace_prefix(location, HoldDesk.base_url() <> "/", "")

  defp post_event(conn, location, body, headers \\ []) do
    conn =
      Enum.reduce([{"content-type", @form} | headers], conn, fn {name, value}, conn ->
        put_req_header(conn, name, value)
      end)

    post(conn, "/basichttp/" <> token(location), body)
  end

  defp status!(execution_id) do
    {:ok, record} = Storage.fetch_execution(FirstWorkflow.store(), execution_id)
    Execution.from_record(record).status
  end

  # sabotage: the :basichttp key dropped from HoldDesk.config/0 -> the
  # chart's basichttp send was an unsupported type, no desk_post arrived
  # and the route answered an error, red; restored, green.
  # sabotage: execute/2's BasicHTTP clause made to answer :ok without
  # performing -> assert_received {:desk_post, ...} failed, red; restored,
  # green.
  test "the hold tells the desk it was placed, with its own location to answer at" do
    {execution_id, headers, params} = placed_hold()

    assert params["_scxmleventname"] == "hold.placed"
    assert params["hold_id"] == "hold-0417"
    assert params["copy_id"] == "copy-2231"
    assert {:ok, location} = BasicHTTP.location(HoldDesk.config(), execution_id)
    assert params["reply_to"] == location
    assert String.starts_with?(location, HoldDesk.base_url() <> "/")
    refute String.contains?(location, execution_id)
    assert {"content-type", @form} in headers
    assert Enum.any?(headers, &match?({"scxml-send-key", _key}, &1))
    assert status!(execution_id) == :active
  end

  # sabotage: the controller handed the front the parsed body ("") instead
  # of the raw one -> the event decoded as HTTP.POST, the execution stayed
  # active, red; restored, green.
  # sabotage: Front.response/1's status replaced with a constant 200 in the
  # controller -> red on the 204; restored, green.
  test "a POST at the location through the controller delivers the desk's event", %{conn: conn} do
    {execution_id, _headers, %{"reply_to" => location}} = placed_hold()

    conn = post_event(conn, location, "_scxmleventname=copy.shelved")

    assert response(conn, 204) == ""
    assert status!(execution_id) == :completed

    assert {:ok, [_requested, %{event: %{name: "copy.shelved"}}]} =
             Executions.inputs(FirstWorkflow.store(), execution_id)
  end

  test "a finished hold and an unknown location answer 404", %{conn: conn} do
    {_execution_id, _headers, %{"reply_to" => location}} = placed_hold()

    assert conn |> post_event(location, "_scxmleventname=copy.shelved") |> response(204)

    assert build_conn() |> post_event(location, "_scxmleventname=copy.shelved") |> response(404)

    unknown = HoldDesk.base_url() <> "/" <> BasicHTTP.mint_token()
    assert build_conn() |> post_event(unknown, "_scxmleventname=copy.shelved") |> response(404)
  end

  # Ecto's own query lines are set aside: at :debug they print bound
  # parameters, which the guide says. They also prove the capture is live.
  # sabotage: the endpoint's Plug.Telemetry log option removed -> the
  # request line carried the token, red; restored, green.
  # sabotage: the route's log: false removed and "token" dropped from
  # :filter_parameters -> the dispatch params carried the token, red;
  # restored, green.
  test "a POST at the location leaves the token out of the request log", %{conn: conn} do
    {_execution_id, _headers, %{"reply_to" => location}} = placed_hold()
    level = Logger.level()
    Logger.configure(level: :debug)
    on_exit(fn -> Logger.configure(level: level) end)

    log =
      capture_log([level: :debug], fn ->
        assert conn |> post_event(location, "_scxmleventname=copy.shelved") |> response(204)
      end)

    {queries, others} =
      log
      |> String.split(~r/^(?=\d{2}:\d{2}:\d{2}\.\d{3} )/m, trim: true)
      |> Enum.split_with(&(&1 =~ ~r/\] QUERY (OK|ERROR)/))

    assert queries != []
    refute Enum.any?(others, &(&1 =~ token(location)))
  end

  # sabotage: the controller handed the front "POST" whatever the method
  # -> the GET was delivered and answered 204, red; restored, green.
  test "another method answers 405 with allow: POST", %{conn: conn} do
    {execution_id, _headers, %{"reply_to" => location}} = placed_hold()

    conn = get(conn, "/basichttp/" <> token(location))

    assert response(conn, 405) == ""
    assert get_resp_header(conn, "allow") == ["POST"]
    assert status!(execution_id) == :active
  end

  test "a malformed send key answers 400 and delivers nothing", %{conn: conn} do
    {execution_id, _headers, %{"reply_to" => location}} = placed_hold()

    conn =
      post_event(conn, location, "_scxmleventname=copy.shelved", [
        {"scxml-send-key", "not-eight-fields"}
      ])

    assert response(conn, 400) == ""
    assert status!(execution_id) == :active
  end

  test "a repeated send key is delivered once", %{conn: conn} do
    {execution_id, _headers, %{"reply_to" => location}} = placed_hold()
    key = [{"scxml-send-key", "sess_desk/shelved_1/1/1/0/0/onentry.0.0/0"}]

    assert conn |> post_event(location, "_scxmleventname=noted", key) |> response(204)
    assert build_conn() |> post_event(location, "_scxmleventname=noted", key) |> response(204)

    assert {:ok, [_requested, %{event: %{name: "noted"}}]} =
             Executions.inputs(FirstWorkflow.store(), execution_id)
  end

  # The chart has two finals, and a finished execution keeps no
  # configuration to read the one it took from; the error.communication
  # the refused POST re-entered is what names desk_unreached, since only
  # that event leads there.
  # sabotage: execute/2 made to answer :ok whatever perform/2 answered ->
  # the execution stayed active in waiting and the location still took a
  # POST, red; restored, green.
  # sabotage: perform/3 made to continue past a failed POST -> no
  # error.communication was re-entered, red; restored, green.
  test "a desk that refuses the POST ends the hold unreached", %{conn: conn} do
    reentered = [:statifier_persistence, :execution, :step, :reentered]
    handler = "hold-desk-reentered-#{System.unique_integer([:positive])}"
    test_pid = self()

    forward = fn _event, _measurements, metadata, nil ->
      send(test_pid, {:reentered, metadata})
    end

    :ok = :telemetry.attach(handler, reentered, forward, nil)
    on_exit(fn -> :telemetry.detach(handler) end)

    Process.put(:desk_status, 503)
    {execution_id, _headers, %{"reply_to" => location}} = placed_hold("hold-0418")

    assert_received {:reentered,
                     %{execution_id: ^execution_id, name: "error.communication", opts: opts}}

    assert is_binary(opts[:sendid])
    assert status!(execution_id) == :completed
    assert conn |> post_event(location, "_scxmleventname=copy.shelved") |> response(404)
  end

  # Statifier plans a send with no target as an error.communication raise
  # and no request; the executor fails the send instead of performing it.
  # sabotage: perform/3's raise clause made to continue -> execute/2
  # answered :ok, red; restored, green.
  test "a send with no target posts nothing and fails, naming the send" do
    no_target = %Statifier.Effect.Send{
      type: "basichttp",
      event: "hold.placed",
      target: nil,
      data: %{"hold_id" => "hold-0419"},
      send_id: "send_1",
      c_index: 0,
      owner: {:transition, 0},
      macrostep: 1,
      microstep: 0,
      round: 0,
      ordinal: 0
    }

    assert HoldDesk.execute({:send, no_target}, %{execution_id: "ex_hold_0419"}) ==
             {:error, {:basichttp_send_without_target, "send_1"}}

    refute_received {:desk_post, _url, _headers, _body}
  end

  # sabotage: :basichttp added to RoutedWorkflow's configuration -> red;
  # restored, green.
  test "the parcel configuration carries no BasicHTTP location" do
    assert RoutedWorkflow.config().basichttp == nil
    assert HoldDesk.config().basichttp[:base_url] == HoldDesk.base_url()
  end
end
