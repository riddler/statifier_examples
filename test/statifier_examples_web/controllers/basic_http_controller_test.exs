defmodule StatifierExamplesWeb.BasicHTTPControllerTest do
  use StatifierExamplesWeb.ConnCase, async: false

  import Ecto.Query, only: [from: 2]
  import ExUnit.CaptureLog

  alias StatifierExamples.{DeskTransport, FirstWorkflow, HoldDesk, Repo, RoutedWorkflow}
  alias StatifierExamples.HoldDesk.DeskPost
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

  # The hold request's delivery returns before the desk is told: the POST
  # is a job, performed when the test drains the desk's queue.
  defp requested_hold(hold_id) do
    assert {:ok, [{:created_and_delivered, "hold_requests", execution_id}]} =
             HoldDesk.request(@scope, %{
               "hold_id" => hold_id,
               "copy_id" => "copy-2231",
               "desk" => @desk
             })

    execution_id
  end

  defp drain_desk_posts,
    do: Oban.drain_queue(queue: :desk_posts, with_scheduled: true, with_recursion: true)

  defp placed_hold(hold_id \\ "hold-0417") do
    execution_id = requested_hold(hold_id)
    assert %{success: 1, failure: 0} = drain_desk_posts()
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
  # inserting the job -> nothing drained and no desk_post arrived, red;
  # restored, green.
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

  # The delivery returns, and so has committed, before the desk is called;
  # the desk is then called with no transaction open in the process that
  # calls it, so however long it takes to answer it holds no delivery.
  # sabotage: the executor made to perform the POST itself instead of
  # inserting the job -> the desk was called before the delivery returned,
  # red; restored, green.
  # sabotage: the job's POST wrapped in a Repo transaction -> the desk was
  # called inside one, red; restored, green.
  test "a slow desk holds no delivery open: the POST is made after the commit" do
    test_pid = self()

    Process.put(:desk_answering, fn ->
      send(test_pid, {:desk_answering, Repo.in_transaction?()})
    end)

    execution_id = requested_hold("hold-0420")

    refute_received {:desk_answering, _in_transaction}
    refute_received {:desk_post, _url, _headers, _body}
    assert status!(execution_id) == :active
    assert [%{"execution_id" => ^execution_id}] = desk_post_args()

    assert %{success: 1, failure: 0} = drain_desk_posts()
    assert_received {:desk_answering, false}
    assert_received {:desk_post, @desk, _headers, _body}
  end

  # The chart has two finals, and a finished execution keeps no
  # configuration to read the one it took from; the error.communication
  # the job delivered is what names desk_unreached, since only that event
  # leads there. It arrives as a delivered external event, in a step of
  # its own, so it is in the execution's input log under the send's id.
  # sabotage: the job's last failed POST made to cancel instead of
  # delivering error.communication -> the hold stayed waiting, red;
  # restored, green.
  test "a desk that refuses the POST ends the hold unreached", %{conn: conn} do
    Process.put(:desk_status, 503)
    execution_id = requested_hold("hold-0418")

    assert %{success: 1, failure: 2} = drain_desk_posts()
    assert_received {:desk_post, @desk, _headers, body}
    %{"reply_to" => location} = URI.decode_query(body)

    assert {:ok,
            [
              %{event: %{name: "hold.requested"}},
              %{event: %{name: "error.communication", sendid: sendid}}
            ]} = Executions.inputs(FirstWorkflow.store(), execution_id)

    assert is_binary(sendid)
    assert status!(execution_id) == :completed
    assert conn |> post_event(location, "_scxmleventname=copy.shelved") |> response(404)
  end

  # sabotage: the job's unique option removed -> two jobs, red; restored,
  # green.
  test "a redriven send inserts one job, keyed on the send's dedup key" do
    send = hold_send("https://riverside.example/holds-desk")

    assert :ok = HoldDesk.execute({:send, send}, %{execution_id: "ex_hold_0421"})
    assert :ok = HoldDesk.execute({:send, send}, %{execution_id: "ex_hold_0421"})

    assert [%{"key" => "ex_hold_0421/send_1/1/0/0/0/transition.0/0", "send_id" => "send_1"}] =
             desk_post_args()
  end

  # A job queued before a restart can name an atom this node has not
  # created since. The instruction here is written with a placeholder atom
  # whose bytes are then swapped for a name of the same length that no
  # code creates, so the job decodes it as a node meeting it for the first
  # time would.
  # sabotage: the job's decode given [:safe] -> the instruction was refused
  # and no POST was made, red; restored, green.
  test "a job queued before a restart posts, whatever atoms this node has" do
    payload_ctx =
      {{:post,
        %{
          url: @desk,
          headers: [{"content-type", @form}],
          body: "_scxmleventname=hold.placed",
          transport: DeskTransport,
          send: hold_send(@desk)
        }}, %{session_id: "ex_hold_0424", opts: [], restart_marker: :zz_desk_placeholder_atom}}

    unseen = "zz_desk_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    assert byte_size(unseen) == byte_size("zz_desk_placeholder_atom")

    instruction =
      payload_ctx
      |> :erlang.term_to_binary()
      |> :binary.replace("zz_desk_placeholder_atom", unseen)

    assert_raise ArgumentError, fn -> :erlang.binary_to_term(instruction, [:safe]) end

    {:ok, _job} =
      %{
        "execution_id" => "ex_hold_0424",
        "send_id" => "send_1",
        "key" => "ex_hold_0424/send_1/1/0/0/0/transition.0/0",
        "instruction" => Base.encode64(instruction)
      }
      |> DeskPost.new()
      |> Oban.insert()

    assert %{success: 1, failure: 0} = drain_desk_posts()
    assert_received {:desk_post, @desk, _headers, "_scxmleventname=hold.placed"}
  end

  # The executor runs inside the delivery's transaction, and the job is
  # inserted through the same repo, so a delivery that rolls back takes
  # the job with it and no POST is made for it.
  # sabotage: the insert moved to a Task outside the transaction -> the
  # sandbox refused the Task a connection, so every hold test errored
  # before any assertion; a sandboxed suite has one connection and cannot
  # show this test red. Restored, green.
  test "a delivery that rolls back takes its desk post with it" do
    assert {:error, :rolled_back} =
             Repo.transaction(fn ->
               assert :ok =
                        HoldDesk.execute({:send, hold_send(@desk)}, %{
                          execution_id: "ex_hold_0423"
                        })

               assert [_job] = desk_post_args()
               Repo.rollback(:rolled_back)
             end)

    assert desk_post_args() == []
    assert %{success: 0} = drain_desk_posts()
    refute_received {:desk_post, _url, _headers, _body}
  end

  # A failed POST whose hold has finished, or whose execution has no
  # address row, reaches no execution: the job is cancelled, which keeps it
  # in the jobs table with its reason.
  # sabotage: a missing address row made to answer :ok -> one cancel
  # short, red; restored, green.
  # sabotage: a dropped delivery made to answer :ok -> one cancel short,
  # red; restored, green.
  test "a failed POST that reaches no hold is kept as a dead letter", %{conn: conn} do
    {execution_id, _headers, %{"reply_to" => location}} = placed_hold("hold-0422")
    assert conn |> post_event(location, "_scxmleventname=copy.shelved") |> response(204)

    Process.put(:desk_status, 503)
    send = hold_send(@desk)
    assert :ok = HoldDesk.execute({:send, send}, %{execution_id: execution_id})
    assert :ok = HoldDesk.execute({:send, send}, %{execution_id: "ex_hold_nowhere"})

    assert %{success: 0, failure: 4, cancelled: 2} = drain_desk_posts()
    assert status!(execution_id) == :completed
  end

  # Statifier plans a send with no target as an error.communication raise
  # and no request; the executor fails the send instead of performing it,
  # and plans no job.
  # sabotage: enqueue/3's raise clause made to continue -> execute/2
  # answered :ok, red; restored, green.
  test "a send with no target posts nothing and fails, naming the send" do
    assert HoldDesk.execute({:send, hold_send(nil)}, %{execution_id: "ex_hold_0419"}) ==
             {:error, {:basichttp_send_without_target, "send_1"}}

    assert desk_post_args() == []
    assert %{success: 0} = drain_desk_posts()
    refute_received {:desk_post, _url, _headers, _body}
  end

  defp hold_send(target) do
    %Statifier.Effect.Send{
      type: "basichttp",
      event: "hold.placed",
      target: target,
      data: %{"hold_id" => "hold-0419"},
      send_id: "send_1",
      c_index: 0,
      owner: {:transition, 0},
      macrostep: 1,
      microstep: 0,
      round: 0,
      ordinal: 0
    }
  end

  defp desk_post_args do
    Repo.all(from(job in Oban.Job, where: job.queue == "desk_posts", select: job.args))
  end

  # sabotage: :basichttp added to RoutedWorkflow's configuration -> red;
  # restored, green.
  test "the parcel configuration carries no BasicHTTP location" do
    assert RoutedWorkflow.config().basichttp == nil
    assert HoldDesk.config().basichttp[:base_url] == HoldDesk.base_url()
  end
end
