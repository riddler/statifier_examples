defmodule Mix.Tasks.StatifierExamples.FirstWorkflowFormPost do
  @shortdoc "Runs the form-post first-workflow guide's recipe end to end and prints the trace"

  @moduledoc """
  Runs the recipe in `docs/guides/first-workflow-form-post.md` against this
  app's own database and Oban instance, checks every step, and prints the
  trace.

      mix statifier_examples.first_workflow_form_post

  The work is `StatifierExamples.FormPost.run/1`; this task starts the
  application, runs it, and prints each line it answers. A step that does
  not hold stops the task with a non-zero exit and names the step.

  `--advance-ms N` takes each drain's clock N milliseconds past now, so a
  deadline timer or a retry due within it runs at once; the default is
  `0`, which waits for them as the dev app does.

  Run `mix ecto.migrate` first: the recipe stores its applications in this
  app's `card_applications` table and routes them through
  `statifier_router`'s tables, which this app's migrations create.
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(argv) do
    {switches, _rest} = OptionParser.parse!(argv, strict: [advance_ms: :integer])

    # The dev configuration logs every query; the recipe's own lines are
    # what this task is for. A level already above `:info` is left alone.
    if Logger.compare_levels(Logger.level(), :info) == :lt do
      Logger.configure(level: :info)
    end

    case StatifierExamples.FormPost.run(Keyword.take(switches, [:advance_ms])) do
      {:ok, lines} ->
        Enum.each(lines, &Mix.shell().info/1)

      {:error, step, reason} ->
        Mix.raise("first workflow form post: step #{step} did not hold: #{inspect(reason)}")
    end
  end
end
