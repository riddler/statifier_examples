defmodule StatifierExamples.FirstWorkflow.NoRoute do
  @moduledoc """
  The route delivery the first-workflow recipe's router configuration
  names. `StatifierRouter.Config.new/1` requires one; the recipe sends
  nothing through the router, so nothing ever reaches it.
  """

  @behaviour StatifierRouter.Route

  @impl StatifierRouter.Route
  def deliver(_route_config, _event, _key), do: :ok
end
