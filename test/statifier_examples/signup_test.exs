defmodule StatifierExamples.SignupTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.{Compiler, Decode}
  alias StatifierExamples.{Charts, Signup}
  alias StatifierExamples.Signup.{Provision, SignupStep}

  # The palette the fixtures are written against: this app's own, which
  # composes the signup types, the card-processing ones, the shared
  # `myapp.notify` and the core vocabulary underneath. The test-only
  # stand-in that stood here until `StatifierExamples.Charts.Messaging`
  # landed (se-rrd) is gone with it.
  defp palette, do: Charts.palette()

  # Sabotage: dropped "myapp.provision" from block_types/0; this went red,
  # then reverted.
  test "block_types/0 registers the two signup-wizard types under their myapp names" do
    assert Signup.block_types() == %{
             "myapp.signup_step" => SignupStep,
             "myapp.provision" => Provision
           }
  end

  # Sabotage: swapped the two entries in @documents; this went red, then
  # reverted.
  test "fixtures/0 lists both documents, keyed and named from the documents themselves" do
    assert [wizard, invitations] = Signup.fixtures()

    assert %{key: "signup_wizard", name: "Signup wizard"} = wizard
    assert %{key: "signup_invitations", name: "Signup invitations"} = invitations
  end

  # Sabotage: pointed load/1 at a file that does not exist; this went red,
  # then reverted.
  test "fixtures/0 answers a decoded document at a readable path" do
    for fixture <- Signup.fixtures() do
      assert %StatifierBlocks.Document{schema_version: 1} = fixture.document
      assert File.exists?(fixture.path)
    end
  end

  # The strict decoder rejects an unexpected key inside a BLOCK, and ignores
  # one in the envelope, so the port strips `_comment` at every depth rather
  # than only off the top. This is where a stray one is caught.
  #
  # Sabotage: put a "_comment" key back on a block in
  # signup_invitations.json; this went red with
  # `{:malformed_block, _, {:unexpected_key, "_comment"}}`, then reverted.
  test "every shipped fixture decodes strictly" do
    for file <- ["signup_wizard.json", "signup_invitations.json"] do
      path = Path.join([Application.app_dir(:statifier_examples), "priv", "fixtures", file])
      assert {:ok, _document} = Decode.decode(File.read!(path))
    end
  end

  # A compile that returns `{:ok, _}` is the assertion the bead asks for in
  # its strongest form: findings come back as `{:error, findings}`, so no
  # unresolved type and nothing at `:error` severity can hide behind it.
  #
  # Sabotage: renamed "myapp.signup_step" in block_types/0 so the fixture's
  # type no longer resolved; this went red with an unknown-type finding,
  # then reverted.
  test "both fixtures compile against the palette with no findings" do
    for fixture <- Signup.fixtures() do
      assert {:ok, compiled} = Compiler.compile(fixture.document, palette(), [])
      assert compiled.warnings == []
    end
  end

  # Sabotage: hardcoded the `<invoke>` type attribute in Step.emit/3 rather
  # than reading it from config; this went red, then reverted.
  test "the wizard's compiled chart calls both signup handlers" do
    [wizard | _rest] = Signup.fixtures()

    assert {:ok, compiled} = Compiler.compile(wizard.document, palette(), [])
    assert "myapp:signup" in compiled.invoke_types
    assert "myapp:provision" in compiled.invoke_types
  end

  # se-5ep, amended by se-1xc: the wizard's plan branch guards on
  # `signup.plan` and `signup.seats`, and the root has to be declared or
  # the guard raises `error.execution` instead of reading it as undefined.
  # The host used to carry that declaration because a block document had
  # nowhere to put it; sb ADR-0001 decision 11 gave it somewhere, so the
  # document carries it and the host's list is empty. This asserts the
  # record, and the run tests assert what it buys.
  #
  # Sabotage: removed the `signup` entry from `signup_wizard.json`'s
  # `datamodel` key; this went red here and took the two provisioning
  # tests in `DurableTest` with it. Reverted.
  test "the wizard's own bytes declare the root its plan branch guards on" do
    [wizard, invitations] = Signup.fixtures()

    assert Enum.map(wizard.document.datamodel, & &1.id) == ["signup"]
    assert wizard.declare == []
    assert invitations.declare == []
  end

  # Sabotage: dropped the `<param>` from SignupStep.emit/2; this went red,
  # then reverted.
  test "a wizard step sends the step it collects to the handler" do
    [wizard | _rest] = Signup.fixtures()

    assert {:ok, compiled} = Compiler.compile(wizard.document, palette(), [])
    assert compiled.scxml =~ ~s(name="step")
    assert compiled.scxml =~ ~s(expr="'company_details'")
  end
end
