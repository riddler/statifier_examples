defmodule StatifierExamples.ChartsTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.Palette
  alias StatifierExamples.Charts

  # Sabotage: pointed palette/0 at Palette.new(); the core.sequence assertion
  # went red, then reverted.
  test "the palette carries statifier_blocks' core vocabulary" do
    assert %Palette{types: types} = Charts.palette()
    assert Map.has_key?(types, "core.sequence")
    assert Map.has_key?(types, "core.invoke")
  end

  # Sabotage: dropped Messaging.block_types() from registrations/0; this went
  # red, then reverted.
  test "the palette carries every host type both domains register" do
    assert %Palette{types: types} = Charts.palette()

    host =
      types
      |> Map.keys()
      |> Enum.filter(&String.starts_with?(&1, "myapp."))
      |> Enum.sort()

    assert host == [
             "myapp.authorize",
             "myapp.authorize_with_deadline",
             "myapp.balance_check",
             "myapp.capture",
             "myapp.guarded_section",
             "myapp.guarded_step",
             "myapp.intake",
             "myapp.legacy_check",
             "myapp.manual_flag",
             "myapp.notify",
             "myapp.park",
             "myapp.provision",
             "myapp.receipt",
             "myapp.resolve_review",
             "myapp.risk_rating",
             "myapp.signup_step",
             "myapp.three_ds_challenge"
           ]
  end

  # The Card processing group's order is a decision, and
  # `StatifierExamples.CardAuth`'s moduledoc is where it is written down.
  # This case is the other half of that: the list here and the table there
  # are one claim, so a renumbering that does not visit the table goes red.
  #
  # It asserts the ORDER of the names rather than the numbers, and
  # separately that the numbers are 0..n with no gap - the two things the
  # table promises. `statifier_blocks` refuses a duplicate within a group,
  # so uniqueness is already somebody else's assertion.
  #
  # Sabotage: swapped myapp.intake back to 10; this went red naming intake
  # in the wrong position, and nothing else in the suite did. Reverted from
  # a copy.
  test "the Card processing group is listed in the order CardAuth documents" do
    ordered = group_order("Card processing")

    assert Enum.map(ordered, fn {name, _order} -> name end) == [
             "myapp.intake",
             "myapp.authorize",
             "myapp.capture",
             "myapp.receipt",
             "myapp.risk_rating",
             "myapp.balance_check",
             "myapp.three_ds_challenge",
             "myapp.manual_flag",
             "myapp.park",
             "myapp.resolve_review",
             "myapp.legacy_check",
             "myapp.authorize_with_deadline"
           ]

    assert Enum.map(ordered, fn {_name, order} -> order end) ==
             Enum.to_list(0..(length(ordered) - 1))
  end

  # The other two groups carry the same promise and are small enough to
  # spell: an order somebody wrote is contiguous from 0, in every group.
  #
  # Sabotage: gave myapp.provision order 4; this went red on the signup
  # group's number run, then reverted.
  test "every palette group's order runs 0..n with no gap" do
    %Palette{types: types} = Charts.palette()

    groups =
      types
      |> Map.values()
      |> Enum.map(& &1.palette_entry())
      |> Enum.group_by(&Map.get(&1, :group))
      |> Map.delete(nil)

    refute Enum.empty?(groups)

    for {group, entries} <- groups do
      orders = entries |> Enum.map(&Map.get(&1, :order)) |> Enum.sort()

      assert orders == Enum.to_list(0..(length(entries) - 1)),
             "#{group} does not run 0..#{length(entries) - 1}: #{inspect(orders)}"
    end
  end

  # Sabotage: registered "core.wait" against a host module in registrations/0;
  # this went red, then reverted.
  test "no host registration claims a core name" do
    assert %Palette{types: types} = Charts.palette()

    for {name, module} <- types, String.starts_with?(name, "core.") do
      assert inspect(module) =~ "StatifierBlocks.Core."
    end
  end

  # Sabotage: dropped :brand from @themes; this went red, then reverted.
  test "the host offers three theme tokens" do
    assert Charts.themes() == [:light, :dark, :brand]
  end

  # The property that matters for the icon seam, asserted by walking the
  # palette rather than a list of names copied into this file: a block type
  # declares an icon NAME, and a name the host cannot resolve is a tile the
  # editor silently does not draw. Walking the palette is what makes a new
  # block type with a new icon fail here rather than in a screenshot.
  #
  # Sabotage: dropped "bolt.svg" from the wildcard Charts.Icons reads; this
  # went red naming the icon, then reverted.
  test "every icon name the palette declares resolves" do
    %Palette{types: types} = Charts.palette()

    declared =
      types
      |> Map.values()
      |> Enum.map(&Map.get(&1.palette_entry(), :icon))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    # A palette that declared no icons at all would pass every assertion
    # below by vacuity, which is the one way this walk could be green and
    # mean nothing.
    assert length(declared) > 10

    for name <- declared do
      assert Charts.icon(name) == name, "#{name} resolves to no icon"
      assert is_binary(Charts.Icons.body(name))
    end
  end

  # Sabotage: made icon/1 return its argument unconditionally; this went red,
  # then reverted.
  test "a name the icon set does not have resolves to nil" do
    assert Charts.icon("no-such-heroicon") == nil
    assert Charts.icon(:no_such_heroicon) == nil
  end

  # Sabotage: made icon/1 skip the Atom.to_string/1 clause; this went red,
  # then reverted.
  test "the icon seam answers an atom the same way it answers a string" do
    assert Charts.icon(:clock) == "clock"
    assert Charts.icon("clock") == "clock"
  end

  # Sabotage: made fixtures/0 read only Signup.fixtures(); this went red, then
  # reverted.
  test "the fixture list is both domains', card processing first" do
    assert [
             %{key: "card_processing", name: "Card processing"},
             %{key: "card_processing_sketch", name: "Card processing (sketch)"},
             %{key: "card_processing_composite", name: "Card processing (composite)"},
             %{key: "signup_wizard"},
             %{key: "signup_invitations"},
             %{key: "signup_onboarding"},
             %{key: "signup_bulk_invites"},
             %{key: "signup_bulk_invites_strict"},
             %{key: "signup_invite_chunk"},
             %{key: "signup_guarded_step"},
             %{key: "signup_guarded_section"}
           ] = Charts.fixtures()
  end

  # The union of both kinds of handler this app registers: the three sync
  # domain modules the adapter is generated over, and the one full
  # `Statifier.Invoke.Handler` `StatifierExamples.Charts.Subchart` serves
  # (se-4dt.4). The subchart type sorts last, after every `myapp:` name.
  #
  # Sabotage: dropped Signup.Handlers from the sync adapter's handler list;
  # this went red, then reverted.
  test "the invoke-type list is every handler all three registries answer, plus the subchart" do
    assert Charts.invoke_types() == [
             "myapp:authorize",
             "myapp:balance_check",
             "myapp:capture",
             "myapp:intake",
             "myapp:legacy_check",
             "myapp:manual_flag",
             "myapp:notify",
             "myapp:park",
             "myapp:process_rows",
             "myapp:provision",
             "myapp:receipt",
             "myapp:resolve_review",
             "myapp:risk_rating",
             "myapp:signup",
             "myapp:three_ds",
             "statifier_blocks:map",
             "statifier_blocks:subchart"
           ]
  end

  # Sabotage: made fixture/1 raise on an unknown key; this went red, then
  # reverted.
  test "a fixture is found by key, and an unknown key is an ordinary answer" do
    assert {:ok, %{key: "card_processing"}} = Charts.fixture("card_processing")
    assert Charts.fixture("no_such_document") == :error
  end

  # The `{type name, order}` pairs of one palette group, sorted by order -
  # which is the list the drawer draws.
  defp group_order(group) do
    %Palette{types: types} = Charts.palette()

    types
    |> Enum.filter(fn {_name, module} -> Map.get(module.palette_entry(), :group) == group end)
    |> Enum.map(fn {name, module} -> {name, Map.get(module.palette_entry(), :order)} end)
    |> Enum.sort_by(fn {_name, order} -> order end)
  end
end
