defmodule StatifierExamples.Signup.Handlers do
  @moduledoc """
  The host handlers the signup wizard's block types name.

  A block type names an invoke type; a handler runs one, and which handler a
  name resolves to is deployment state supplied per session (statifier-ex
  ADR-0051). This module is the deployment half for this app's signup
  domain, written in the one shape every handler module here uses:
  `invoke_types/0` answers every name it registers, and `handle/2` answers
  one call or refuses a name it does not.

  That shape is the one the runtime asks for. ADR-0051's per-session
  registration is a `%{invoke type => module}` map, so a handler is a
  *module* rather than a closure, and the set the compiler wants as
  `:known_invoke_types` is the same map's keys - which `invoke_types/0`
  answers directly, without a caller reaching into a map of functions to
  find out what this module can do.

  `myapp:signup` logs a line and answers with what its step collected -
  canned values, because there is no form here to fill in, but canned in
  the handler, which is where a real deployment's answers come from. The
  chart writes them wherever the calling block's `assign_to` says, and
  that is how the wizard's plan branch gets a plan to guard on.
  `myapp:provision` is the
  one call in this app that writes - the wizard exists to create an
  account, and a handler that only logged would leave the run having meant
  nothing. Every value that reaches either is fictional -
  `@example.com` addresses and made-up plan names.

  ## The call that writes needs to know which run it is

  `StatifierPersistence.Executor`'s at-least-once contract means a
  provision can be delivered twice, so the write has to be idempotent on
  something stable. Nothing in the chart is: it carries no datamodel and
  no identity. The *run* is, and a durable driver passes it in the call
  context `StatifierExamples.Charts.dispatch/3` takes - which is why the
  provisioning clause matches on `%{run_id: run_id}` and the in-memory
  driver, which has no run to name, gets the clause that says so.

  `StatifierExamples.Signup.Accounts` holds the write and the reasoning
  about the key.
  """

  require Logger

  alias StatifierExamples.Charts
  alias StatifierExamples.Signup.Accounts

  @invoke_types [
    "myapp:provision",
    "myapp:signup"
  ]

  @doc """
  Every invoke type this module answers, sorted.

  Part of the list a host hands the compiler as `:known_invoke_types`,
  which is what turns "this document names a handler nobody registered"
  from a runtime surprise into a compile-time warning.
  """
  @spec invoke_types() :: [String.t()]
  def invoke_types, do: @invoke_types

  @doc """
  Answers one call, or refuses a name this module does not register.

  `{:error, {:unknown_invoke_type, type}}` rather than a raise, because an
  unregistered invoke type is an ordinary answer a caller routes on - this
  family's rule is that errors are events, and a leaf never rescues to a
  default.

  `myapp:signup` collects one step of the wizard, and `params` carries the
  `step` the block emitted as a literal `<param>`, so the handler learns
  which form to put up without reading the datamodel. `myapp:provision`
  creates the workspace the finished signup gets.
  """
  @spec handle(String.t(), map(), Charts.call_context()) ::
          {:ok, map()} | {:error, {:unknown_invoke_type, String.t()}}
  def handle(invoke_type, params, context \\ %{})

  def handle("myapp:signup", params, _context) do
    step = Map.get(params, "step")

    Logger.info("myapp:signup collected step #{inspect(step)}")

    {:ok, answers(step)}
  end

  def handle("myapp:provision", _params, %{run_id: run_id}) when is_binary(run_id) do
    {result, user} = Accounts.provision(run_id)

    Logger.info("myapp:provision #{result} the account #{user.email}")

    {:ok, %{"account" => user.email, "provisioned" => Atom.to_string(result)}}
  end

  # No run to key the write on, so there is nothing durable to write. The
  # in-memory driver is the caller here, and its runs do not outlive the
  # page that started them; provisioning an account from one would leave a
  # row nothing can ever find its way back to.
  def handle("myapp:provision", params, _context) do
    Logger.info(
      "myapp:provision skipped the write for a run-less call, #{inspect(Map.keys(params))}"
    )

    {:ok, %{"provisioned" => "skipped"}}
  end

  def handle(invoke_type, _params, _context),
    do: {:error, {:unknown_invoke_type, invoke_type}}

  # What each step of the wizard comes back with.
  #
  # There is no form here to fill in, so the answers are canned - but they
  # are canned in the HANDLER, which is where a real deployment's answers
  # would come from too. That is the whole of se-dyo: the wizard used to
  # carry a `core.assign` block holding these three values as an object
  # literal, because the handler answered `{:ok, %{}}` and the plan branch
  # downstream had nothing to guard on. A stand-in inside the document
  # taught the reader that a chart invents its own data, which is the one
  # thing this reference embedder should not teach.
  #
  # Only `account` answers with anything. The other four steps are calls
  # whose result the chart keeps nothing of, and the blocks that name them
  # carry no `assign_to`, so an answer from them would be discarded on the
  # way past. Every value is fictional.
  @spec answers(term()) :: map()
  defp answers("account"),
    do: %{"plan" => "business", "seats" => 5, "email_verified" => false}

  defp answers(_step), do: %{}
end
