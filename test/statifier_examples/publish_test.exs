defmodule StatifierExamples.PublishTest do
  @moduledoc """
  `StatifierExamples.Publish.check/2`, this app's publish step, over the
  documents it ships and over three documents in the library world: a
  patron registration whose verification handler reads past its declared
  payload, refused at the first stage; the same registration with the read
  corrected, which publishes; and a branch's overdue-loan sweep whose
  done-data read cannot be checked without a datamodel, which publishes
  with a warning.

  The host state each document is judged against is built here the way a
  host would build it: this app's palette, the fixture's own datamodel and
  `<data>` roots, a router configuration with one registered route, and two
  lookups over the documents this app ships - a child document is
  published as this app compiles a child (`Charts.Subchart.child_compile/1`)
  and nothing declares what it accepts.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Compiled, Decode, Document, Edit}
  alias StatifierExamples.{Charts, Publish}
  alias StatifierExamples.Charts.Subchart

  # A route adapter, so the router configuration registers one route name.
  defmodule NoticeRoute do
    @moduledoc false
    @behaviour StatifierRouter.Route

    @impl true
    def deliver(_route_config, _event, _key), do: :ok
  end

  @send_type "myapp:sink"

  @patron_registration "test/fixtures/patron_registration_undeclared_read.json"

  # The loan reminder a branch runs once per overdue loan, and the sweep
  # that runs it. The sweep's `collect_type` names a type rather than
  # writing its members inline, so with no datamodel to resolve the name
  # against, the done-data keys it reads are unchecked.
  @loan_reminder """
  {
    "schema_version": 1,
    "id": "bdoc_loan_reminder",
    "revision": 1,
    "metadata": {"name": "Loan reminder", "domain": "library_loan"},
    "datamodel": [{"id": "loan"}],
    "root": {
      "type": "core.sequence",
      "id": "blk_lr_root",
      "type_version": 1,
      "slots": {
        "body": [
          {"type": "core.wait", "id": "blk_lr_grace", "type_version": 1,
           "config": {"duration": "1d"}}
        ]
      }
    }
  }
  """

  @overdue_sweep """
  {
    "schema_version": 1,
    "id": "bdoc_branch_overdue_sweep",
    "revision": 1,
    "metadata": {"name": "Overdue sweep", "domain": "library_loan"},
    "datamodel": [{"id": "branch"}],
    "root": {
      "type": "core.sequence",
      "id": "blk_bs_root",
      "type_version": 1,
      "slots": {
        "body": [
          {"type": "core.map", "id": "blk_bs_remind", "type_version": 1,
           "config": {"items": "branch.overdue_loans", "chart": "bdoc_loan_reminder",
                      "collect": "branch.reminders", "collect_type": "LoanReminder",
                      "on": "all"}}
        ]
      }
    }
  }
  """

  setup do
    {:ok, config} =
      StatifierRouter.Config.new(
        repo: StatifierExamples.Repo,
        delivery: NoticeRoute,
        send_type: @send_type,
        route_adapters: %{"branch_notices" => {NoticeRoute, %{}}}
      )

    %{config: config}
  end

  describe "the documents this app ships" do
    # Sabotage: dropped Signup.fixtures/0 from Charts.fixtures/0; this went
    # red. Reverted from a copy.
    test "are the twelve the host lists" do
      assert Enum.map(Charts.fixtures(), & &1.key) == [
               "card_processing",
               "card_processing_sketch",
               "card_processing_composite",
               "signup_wizard",
               "signup_invitations",
               "signup_onboarding",
               "signup_bulk_invites",
               "signup_bulk_invites_strict",
               "signup_invite_chunk",
               "signup_guarded_step",
               "signup_guarded_section",
               "signup_path"
             ]
    end

    # Sabotage: made verdict/2 refuse on a :warning as well as an :error;
    # this went red, and so did the warning case below. Reverted from a copy.
    test "every one but signup_onboarding publishes, with its accepts", %{config: config} do
      for fixture <- Charts.fixtures(), fixture.key != "signup_onboarding" do
        assert {:ok, %Compiled{} = compiled, accepts, warnings} =
                 Publish.check(fixture.document, host(fixture, config)),
               "#{fixture.key} was refused"

        assert accepts == fixture.document.accepts
        assert accepts == compiled.accepts
        assert Enum.all?(warnings, &match?(%{check: _, anchor: _, message: _}, &1))
      end
    end

    # Sabotage: dropped graph_stage/2 from check/2; this went red, and so did
    # the warning case below. Reverted from a copy.
    test "signup_onboarding is refused at the graph stage: the wizard never finishes abandon",
         %{config: config} do
      {:ok, fixture} = Charts.fixture("signup_onboarding")

      assert {:refused, %{stage: :graph, findings: [finding]}} =
               Publish.check(fixture.document, host(fixture, config))

      assert %{check: :graph, anchor: {:config, "blk_so_wizard", "outcomes"}, message: message} =
               finding

      assert message =~ ~s("bdoc_signup_demo")
      assert message =~ ~s("abandon")
    end
  end

  describe "a patron registration that reads past its declared payload" do
    # Sabotage: dropped findings_stage/3 from check/2; this went red and
    # nothing else in the file did. Reverted from a copy.
    test "is refused at the first stage, on the capture that reads it", %{config: config} do
      document = patron_registration()

      assert {:refused, %{stage: :findings, findings: [finding]}} =
               Publish.check(document, library_host(config))

      assert %{check: :config, anchor: {:config, "blk_pr_verified", "capture"}} = finding
      assert finding.message =~ "email"
    end

    # Sabotage: made check/2 answer [] in place of the compiled accepts;
    # this went red. Reverted from a copy.
    test "publishes once the payload declares what the capture reads, with its accepts",
         %{config: config} do
      document = declare_email(patron_registration())

      assert {:ok, %Compiled{}, ["email.verified"], []} =
               Publish.check(document, library_host(config))
    end

    # Sabotage: made accepts_stage/2 answer :ok whatever was unreachable;
    # this went red. Reverted from a copy.
    test "is refused at the accepts stage when it declares an event it never takes",
         %{config: config} do
      document = %Document{declare_email(patron_registration()) | accepts: ["email.bounced"]}

      assert {:refused, %{stage: :accepts, findings: [finding]}} =
               Publish.check(document, library_host(config))

      assert finding == %{
               check: :unreachable_accepts,
               anchor: {:accepts, "email.bounced"},
               message:
                 ~s(the document accepts "email.bounced" and no transition in its chart takes it)
             }
    end
  end

  describe "a done-data read that cannot be checked" do
    # Sabotage: made verdict/2 treat a :warning as an :error; this went red.
    # Reverted from a copy.
    test "publishes, and the graph stage's warning arrives in warnings", %{config: config} do
      reminder = decode!(@loan_reminder)
      {:ok, reminder_compiled} = Subchart.child_compile(reminder)

      resolver = fn
        "bdoc_loan_reminder" -> {:ok, reminder_compiled}
        _other -> {:error, :not_published}
      end

      host = %{library_host(config) | document_resolver: resolver}

      assert {:ok, %Compiled{}, [], [warning]} = Publish.check(decode!(@overdue_sweep), host)

      assert %{check: :graph, anchor: {:config, "blk_bs_remind", "collect_type"}} = warning
      assert warning.message =~ ~s("LoanReminder")
    end
  end

  # The host state for a shipped fixture: its own datamodel and roots, and
  # a document resolver over every document this app ships.
  defp host(fixture, config) do
    %{
      palette: Charts.palette(),
      datamodel: fixture.datamodel,
      declare: fixture.declare,
      send_types: %{@send_type => StatifierRouter.SendHandler},
      router_config: config,
      accepts_lookup: fn _document -> {:error, :not_published} end,
      document_resolver: &published/1
    }
  end

  # The same host, for a library-world document this app does not ship: no
  # datamodel document, no roots of the deployment's own.
  defp library_host(config), do: host(%{datamodel: nil, declare: []}, config)

  defp published(document_id) do
    case Enum.find(Charts.fixtures(), &(&1.document.id == document_id)) do
      nil ->
        {:error, :not_published}

      fixture ->
        {:ok, compiled} = Subchart.child_compile(fixture.document)
        {:ok, compiled}
    end
  end

  defp patron_registration, do: decode!(File.read!(@patron_registration))

  # The one field the capture reads, added to the inline payload.
  defp declare_email(document) do
    block = document |> Document.blocks() |> Enum.find(&(&1.id == "blk_pr_verified"))
    payload = block.config["payload"] ++ [%{"name" => "email", "type" => "string"}]

    {:ok, corrected, _inverse} =
      Edit.apply(
        document,
        {:update_config, "blk_pr_verified", Map.put(block.config, "payload", payload)}
      )

    corrected
  end

  defp decode!(json) do
    {:ok, document} = Decode.decode(json)
    document
  end
end
