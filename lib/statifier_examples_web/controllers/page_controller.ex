defmodule StatifierExamplesWeb.PageController do
  use StatifierExamplesWeb, :controller

  alias StatifierExamples.Charts

  @doc """
  The documents index: every fixture this app ships, linked into the editor
  host page.

  It is a plain controller rather than a LiveView on purpose - the page has no
  state and nothing on it changes - and the links carry only `?doc=`, so the
  theme falls back to light the way any other unparameterized visit does.
  """
  def home(conn, _params) do
    render(conn, :home, fixtures: Charts.fixtures())
  end
end
