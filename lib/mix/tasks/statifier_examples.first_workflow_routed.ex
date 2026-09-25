defmodule Mix.Tasks.StatifierExamples.FirstWorkflowRouted do
  @shortdoc "Runs the routed first-workflow guide's recipe end to end and prints the trace"

  @moduledoc """
  Runs the recipe in `docs/guides/first-workflow-routed.md` against this
  app's own database and Oban instance, checks every step, and prints the
  trace.

      mix statifier_examples.first_workflow_routed

  The work is `StatifierExamples.RoutedWorkflow.run/1`; this task starts
  the application, runs it, and prints each line it answers. A step that
  does not hold stops the task with a non-zero exit and names the step.

  Run `mix ecto.migrate` first: the recipe routes through
  `statifier_router`'s tables, which this app's migration
  `20260925120001_add_statifier_router` creates.
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(_argv) do
    # The dev configuration logs every query; the recipe's own lines are
    # what this task is for. A level already above `:info` is left alone.
    if Logger.compare_levels(Logger.level(), :info) == :lt do
      Logger.configure(level: :info)
    end

    case StatifierExamples.RoutedWorkflow.run() do
      {:ok, lines} ->
        Enum.each(lines, &Mix.shell().info/1)

      {:error, step, reason} ->
        Mix.raise("first workflow routed: step #{step} did not hold: #{inspect(reason)}")
    end
  end
end
